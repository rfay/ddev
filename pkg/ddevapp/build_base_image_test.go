package ddevapp

import (
	"os"
	"path/filepath"
	"runtime"
	"testing"

	composeTypes "github.com/compose-spec/compose-go/v2/types"
	"github.com/stretchr/testify/require"
)

// TestResolveBuildBaseImages checks that a build service's base images come
// from its Dockerfile, resolved the way BuildKit resolves them.
func TestResolveBuildBaseImages(t *testing.T) {
	for _, tc := range []struct {
		name       string
		dockerfile string
		args       []string
		target     string
		expected   []string
	}{
		{"ARG default", "ARG BASE=debian\nFROM $BASE\n", nil, "", []string{"debian:latest"}},
		{"build arg overrides a default used by a later ARG", "ARG A=debian\nARG B=${A}:12\nFROM $B\n", []string{"A=ubuntu"}, "", []string{"ubuntu:12"}},
		{"reachable stages and COPY --from images, deduplicated", "FROM golang:1.25 AS builder\nFROM alpine:3.20 AS unused\nFROM golang:1.25\nCOPY --from=builder /a /a\nCOPY --from=busybox:1 /b /b\n", nil, "", []string{"busybox:1", "golang:1.25"}},
		{"build target skips later stages", "FROM debian:12 AS base\nFROM alpine:3.20\n", nil, "base", []string{"debian:12"}},
		{"scratch has nothing to pull", "FROM scratch\n", nil, "", []string{}},
		{"unparseable Dockerfile", "RUN true\n", nil, "", nil},
	} {
		t.Run(tc.name, func(t *testing.T) {
			service := composeTypes.ServiceConfig{Build: &composeTypes.BuildConfig{
				DockerfileInline: tc.dockerfile,
				Args:             composeTypes.NewMappingWithEquals(tc.args),
				Target:           tc.target,
			}}
			require.Equal(t, tc.expected, resolveBuildBaseImages(service))
		})
	}

	t.Run("platform ARGs, build platforms and additional contexts", func(t *testing.T) {
		service := composeTypes.ServiceConfig{Build: &composeTypes.BuildConfig{
			DockerfileInline:   "FROM tool:$BUILDARCH AS tool\nFROM golang:1.25-$TARGETARCH\nCOPY --from=tool /t /t\nCOPY --from=pinned /a /a\nCOPY --from=localdir /b /b\n",
			AdditionalContexts: composeTypes.Mapping{"pinned": "docker-image://alpine:3.20", "localdir": "./files"},
		}}
		require.Equal(t, []string{"alpine:3.20", "golang:1.25-" + runtime.GOARCH, "tool:" + runtime.GOARCH}, resolveBuildBaseImages(service))
		service.Build.Platforms = []string{"linux/amd64", "linux/arm64"}
		require.Equal(t, []string{"alpine:3.20", "golang:1.25-amd64", "golang:1.25-arm64", "tool:" + runtime.GOARCH}, resolveBuildBaseImages(service))
	})

	t.Run("Dockerfile on disk", func(t *testing.T) {
		dir := t.TempDir()
		require.NoError(t, os.WriteFile(filepath.Join(dir, "Dockerfile.custom"), []byte("FROM debian:12\n"), 0644))
		service := composeTypes.ServiceConfig{Build: &composeTypes.BuildConfig{Context: dir, Dockerfile: "Dockerfile.custom"}}
		require.Equal(t, []string{"debian:12"}, resolveBuildBaseImages(service))
		service.Build.Dockerfile = "missing"
		require.Nil(t, resolveBuildBaseImages(service))
	})

	t.Run("no build section", func(t *testing.T) {
		require.Nil(t, resolveBuildBaseImages(composeTypes.ServiceConfig{Image: "debian"}))
	})
}

// TestBuildBaseImageCallers checks that a build service is reported by its
// base image whatever its image tag is, per #8832.
func TestBuildBaseImageCallers(t *testing.T) {
	app := &DdevApp{Name: "acme", ComposeYaml: &composeTypes.Project{
		Services: composeTypes.Services{
			"pi": {
				Image: "ddev-pi-acme-built",
				Build: &composeTypes.BuildConfig{DockerfileInline: "FROM ubuntu:24.04\n"},
			},
			"db": {Image: "mariadb:11.8-acme-built"},
		},
	}}
	images, err := app.FindAllImages()
	require.NoError(t, err)
	require.ElementsMatch(t, []string{"ubuntu:24.04", "mariadb:11.8"}, images)
	require.Equal(t, "ubuntu:24.04", app.describeServiceImage("pi", "ddev-pi-acme-built"))
	require.Equal(t, "mariadb:11.8", app.describeServiceImage("db", "mariadb:11.8-acme-built"))
}
