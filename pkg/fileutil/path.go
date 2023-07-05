package fileutil

import (
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
)

// RemoveAllExcept removes all files and folders in path except the ones
// matching an exception. The argument exceptions is a slice of match patterns
// used as argument pattern for filepath.Match().
//
// Examples:
//
// * to preserve a folder but not its files and sub folders use "my-folder"
// * to preserve a folder and its files and sub folders use "my-folder/*"
func RemoveAllExcept(path string, exceptions []string) error {
	// Normalize path.
	path = filepath.ToSlash(path)

	// Normalize exceptions.
	normalizedExceptions := make([]string, 0, len(exceptions))
	for _, exception := range exceptions {
		// Check exception is not absolute.
		if filepath.IsAbs(exception) {
			return fmt.Errorf("invalid exception `%s`, exceptions must be relative to path", exception)
		}

		// Check exception is well-formed.
		if _, err := filepath.Match(exception, ""); err != nil {
			return fmt.Errorf("invalid exception `%s`: %v", exception, err)
		}

		// Normalize exception and make it absolute.
		normalizedExceptions = append(normalizedExceptions, filepath.Join(path, filepath.ToSlash(exception)))
	}

	// Walk path and remove non excepted.
	return filepath.WalkDir(path, func(current_path string, d fs.DirEntry, err error) error {
		// Normalize current_path.
		current_path = filepath.ToSlash(current_path)

		// Skip the root, we only like to remove the content.
		if path == current_path {
			return nil
		}

		for _, exception := range normalizedExceptions {
			// exception matches a sub folder of current_path. Using strings
			// here is fine because we have normalized paths and there is no
			// func available in filepath.
			if strings.HasPrefix(exception, current_path) {
				return nil
			}

			// exception matches current_path.
			matched, _ := filepath.Match(exception, current_path)
			if matched {
				return filepath.SkipDir
			}

			// exception matches file or folder in current_path.
			matched, _ = filepath.Match(exception, filepath.Join(current_path, "dummy"))
			if matched {
				return filepath.SkipDir
			}
		}

		// No match, remove path recursive.
		return os.RemoveAll(current_path)
	})
}
