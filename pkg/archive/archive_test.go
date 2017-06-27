package archive_test

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/drud/ddev/pkg/archive"
	"github.com/drud/ddev/pkg/testcommon"
	"github.com/stretchr/testify/assert"
)

// TestUnarchive tests unzip/tar/tar.gz/tgz functionality, including the starting extraction-skip directory
func TestUnarchive(t *testing.T) {

	// testUnarchiveDir is the directory we may want to use to start extracting.
	testUnarchiveDir := "dir2/"

	assert := assert.New(t)

	for _, suffix := range []string{"zip", "tar", "tar.gz", "tgz"} {
		source := filepath.Join("testdata", "testfile"+"."+suffix)
		exDir := testcommon.CreateTmpDir("testfile" + suffix)

		// default function to untar
		unarchiveFunc := archive.Untar
		if suffix == "zip" {
			unarchiveFunc = archive.Unzip
		}

		err := unarchiveFunc(source, exDir, "")
		assert.NoError(err)

		// Make sure that our base extraction directory is there
		finfo, err := os.Stat(filepath.Join(exDir, testUnarchiveDir))
		assert.NoError(err)
		assert.True(err == nil && finfo.IsDir())
		finfo, err = os.Stat(filepath.Join(exDir, testUnarchiveDir, "dir2_file.txt"))
		assert.NoError(err)
		assert.True(err == nil && !finfo.IsDir())

		_ = os.RemoveAll(exDir)

		// Now do the unarchive with an extraction root
		exDir = testcommon.CreateTmpDir("testfile" + suffix + "2")

		err = unarchiveFunc(source, exDir, testUnarchiveDir)
		assert.NoError(err)

		// Only the dir2_file should remain
		finfo, err = os.Stat(filepath.Join(exDir, "dir2_file.txt"))
		assert.NoError(err)
		assert.True(err == nil && !finfo.IsDir())

		_ = os.RemoveAll(exDir)
	}

}
