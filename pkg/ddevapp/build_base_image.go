package ddevapp

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"sync"

	composeTypes "github.com/compose-spec/compose-go/v2/types"
	"github.com/containerd/platforms"
	"github.com/distribution/reference"
	"github.com/moby/buildkit/client/llb/sourceresolver"
	"github.com/moby/buildkit/frontend/dockerfile/dockerfile2llb"
	digest "github.com/opencontainers/go-digest"
	ocispecs "github.com/opencontainers/image-spec/specs-go/v1"
)

// describeServiceImage names a service's image for `ddev describe`: its build
// base images when it has any, otherwise its image without the "-built" suffix.
func (app *DdevApp) describeServiceImage(serviceName, image string) string {
	if app.ComposeYaml != nil {
		if baseImages := resolveBuildBaseImages(app.ComposeYaml.Services[serviceName]); len(baseImages) > 0 {
			return strings.Join(baseImages, ", ")
		}
	}
	return strings.TrimSuffix(image, fmt.Sprintf("-%s-built", app.Name))
}

// resolveBuildBaseImages returns the images a compose service's `build:`
// section pulls, read from its Dockerfile instead of guessed from its `image:`
// tag. BuildKit's own Dockerfile frontend does the resolution, so the result
// matches a real build. It returns nil when there is no build section or the
// Dockerfile can't be read or parsed, and an empty slice for `FROM scratch`.
func resolveBuildBaseImages(service composeTypes.ServiceConfig) []string {
	if service.Build == nil {
		return nil
	}
	content, err := readDockerfile(service.Build)
	if err != nil {
		return nil
	}
	targets, err := platforms.ParseAll(service.Build.Platforms)
	if err != nil {
		return nil
	}
	// Compose builds for the host unless `build.platforms` is set. The host is
	// passed as the build platform too, or BuildKit would use the target there.
	host := []ocispecs.Platform{platforms.DefaultSpec()}
	if len(targets) == 0 {
		targets = host
	}

	recorder := &baseImageRecorder{images: []string{}, contexts: service.Build.AdditionalContexts}
	for _, target := range targets {
		_, err := dockerfile2llb.Dockerfile2LLB(context.Background(), content, dockerfile2llb.ConvertOpt{
			BuildArgs:      service.Build.Args.ToMapping(),
			Target:         service.Build.Target,
			BuildPlatforms: host,
			TargetPlatform: &target,
			MetaResolver:   recorder,
		})
		if err != nil {
			return nil
		}
	}
	slices.Sort(recorder.images)
	return slices.Compact(recorder.images)
}

// readDockerfile returns a build's inline Dockerfile, or reads the one it
// names, which compose resolves against the build context.
func readDockerfile(build *composeTypes.BuildConfig) ([]byte, error) {
	if build.DockerfileInline != "" {
		return []byte(build.DockerfileInline), nil
	}
	dockerfile := build.Dockerfile
	if !filepath.IsAbs(dockerfile) {
		dockerfile = filepath.Join(build.Context, dockerfile)
	}
	return os.ReadFile(dockerfile)
}

// baseImageRecorder stands in for BuildKit's registry lookup: it records each
// image the Dockerfile needs and answers with an empty config, so nothing is
// fetched. BuildKit calls it from several goroutines at once.
type baseImageRecorder struct {
	mu       sync.Mutex
	images   []string
	contexts composeTypes.Mapping
}

func (r *baseImageRecorder) ResolveImageConfig(_ context.Context, ref string, _ sourceresolver.Opt) (string, digest.Digest, []byte, error) {
	named, err := reference.ParseNormalizedNamed(ref)
	if err != nil {
		return "", "", nil, err
	}
	image := reference.FamiliarString(named)
	// A compose `additional_contexts` entry replaces the image of that name,
	// matched without the ":latest" BuildKit adds to an untagged name.
	if source, ok := r.contexts[strings.TrimSuffix(image, ":latest")]; ok {
		if image, ok = strings.CutPrefix(source, "docker-image://"); !ok {
			return ref, "", []byte("{}"), nil
		}
	}
	r.mu.Lock()
	r.images = append(r.images, image)
	r.mu.Unlock()
	return ref, "", []byte("{}"), nil
}
