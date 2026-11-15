package main

import (
	"context"
	"testing"

	"github.com/modelcontextprotocol/go-sdk/mcp"
)

func TestServerInitializesWithLifeMCPIdentity(t *testing.T) {
	serverTransport, clientTransport := mcp.NewInMemoryTransports()
	serverSession, err := newServer().Connect(context.Background(), serverTransport, nil)
	if err != nil {
		t.Fatalf("connect server: %v", err)
	}
	defer serverSession.Close()

	client := mcp.NewClient(&mcp.Implementation{Name: "test-client", Version: "0.1.0"}, nil)
	clientSession, err := client.Connect(context.Background(), clientTransport, nil)
	if err != nil {
		t.Fatalf("connect client: %v", err)
	}
	defer clientSession.Close()

	if got := clientSession.InitializeResult().ServerInfo.Name; got != "life-mcp" {
		t.Errorf("server name = %q, want %q", got, "life-mcp")
	}
}
