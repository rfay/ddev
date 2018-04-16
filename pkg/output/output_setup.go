package output

import (
	"github.com/mattn/go-colorable"
	"os"

	log "github.com/sirupsen/logrus"
)

var (
	// UserOut is the customized logrus log used for direct user output
	UserOut = log.New()
	// UserOutFormatter is the specialized formatter for UserOut
	UserOutFormatter = new(TextFormatter)
	// JSONOutput is a bool telling whether we're outputting in json. Set by command-line args.
	JSONOutput = false
)

// LogSetUp sets up UserOut and log loggers as needed by ddev
func LogSetUp() {
	// Use stdout instead of stderr for all user output
	UserOut.Out = os.Stdout
	log.SetOutput(colorable.NewColorableStdout())

	if !JSONOutput {
		UserOut.Formatter = new(log.TextFormatter)
	} else {
		UserOut.Formatter = &JSONFormatter{}
		log.SetOutput(os.Stdout)
	}

	UserOutFormatter.DisableTimestamp = true
	// Always use log.DebugLevel for UserOut
	UserOut.Level = log.DebugLevel // UserOut will by default always output

	// But we use custom DRUD_DEBUG-settable loglevel for log
	logLevel := log.InfoLevel
	drudDebug := os.Getenv("DRUD_DEBUG")
	if drudDebug != "" {
		logLevel = log.DebugLevel
	}
	log.SetLevel(logLevel)
}
