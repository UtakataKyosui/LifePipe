package main

import (
	"context"
	"log"

	"github.com/modelcontextprotocol/go-sdk/mcp"
)

func main() {
	if err := newServer().Run(context.Background(), &mcp.StdioTransport{}); err != nil {
		log.Fatal(err)
	}
}

func newServer() *mcp.Server {
	return mcp.NewServer(&mcp.Implementation{
		Name:    "life-mcp",
		Version: "0.1.0",
	}, nil)
}
