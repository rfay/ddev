package main

import (
	"github.com/ddev/ddev/cmd/ddev/cmd"
	"github.com/ddev/ddev/pkg/amplitude"
	"github.com/ddev/ddev/pkg/util"
	"net/http"
	"os"
	"runtime"
	"runtime/pprof"
)

func main() {

	// Start tracing
	//traceFile, err := os.Create("trace.out")
	//if err != nil {
	//	panic(err)
	//}
	//defer traceFile.Close()
	//
	//if err := trace.Start(traceFile); err != nil {
	//	panic(err)
	//}
	//defer trace.Stop()

	// Create a CPU profile file
	//f, err := os.Create("profile.prof")
	//if err != nil {
	//	panic(err)
	//}
	//defer f.Close()

	// Start CPU profiling
	//if err := pprof.StartCPUProfile(f); err != nil {
	//	panic(err)
	//}
	//defer pprof.StopCPUProfile()

	defer func() {
		numGoroutines := runtime.NumGoroutine()
		util.Debug("number of goroutines at exit: %v", numGoroutines)
		p := pprof.Lookup("goroutine")
		c := p.Count()
		util.Debug("c=%v", c)
		_ = p.WriteTo(os.Stdout, 1)
	}()

	http.DefaultTransport.(*http.Transport).DisableKeepAlives = true

	// Initialization is currently done before via init() func somewhere while
	// creating the ddevapp. This should be cleaned up.
	amplitude.InitAmplitude()

	defer func() {
		amplitude.Flush()
	}()

	// Prevent running as root for most cases
	// We really don't want ~/.ddev to have root ownership, breaks things.
	if os.Geteuid() == 0 && len(os.Args) > 1 && os.Args[1] != "hostname" {
		util.Failed("DDEV is not designed to be run with root privileges, please run as normal user and without sudo")
	}

	cmd.Execute()
}
