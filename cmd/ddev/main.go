package main

import (
	"fmt"
	"github.com/ddev/ddev/pkg/dockerutil"
	"github.com/docker/docker/api/types/container"
	"os"
)

func main() {
	for i := 0; i < 10000; i++ {
		ctx, client := dockerutil.GetDockerClient()
		list, err := client.ContainerList(ctx, container.ListOptions{})
		if err != nil {
			println("failed ContainerList: %v", err)
			os.Exit(5)
		}
		fmt.Printf("containers=%v", list)
	}
}
