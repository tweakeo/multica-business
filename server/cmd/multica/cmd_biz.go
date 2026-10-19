package main

import (
	"encoding/json"
	"fmt"
	"os"
	"strings"

	"github.com/spf13/cobra"
)

// `multica biz` is how agents (and people in a terminal) work with the TLS
// business layer. Every call goes through /api/biz, so the same policies,
// approvals, audit and kill switch apply as in the app.
var bizCmd = &cobra.Command{
	Use:   "biz",
	Short: "Work with the company layer (Empresa): read records and request business actions",
	Long: `Read company data and request business actions.

  multica biz get /overview                     company overview, areas and exceptions
  multica biz get /exceptions?area=ventas       prioritised exception queue
  multica biz get /list/opportunity?stage=propuesta
  multica biz get /record/opportunity/<id>      record with relations, audit and file
  multica biz get /actions                      available actions
  multica biz run <action> '<json payload>'     e.g. contact.touch, message.send

Sensitive actions (sending, issuing, confirming money, publishing) return
"approval_required": a person must approve them in the app. Never try to
achieve the same effect another way.`,
}

var bizGetCmd = &cobra.Command{
	Use:   "get <path>",
	Short: "GET a /api/biz path and print JSON",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		path, err := bizPath(args[0])
		if err != nil {
			return err
		}
		client, err := newAPIClient(cmd)
		if err != nil {
			return err
		}
		var out json.RawMessage
		if err := client.GetJSON(cmd.Context(), path, &out); err != nil {
			return err
		}
		return printRawJSON(out)
	},
}

var bizRunCmd = &cobra.Command{
	Use:   "run <action> [json]",
	Short: "Request a business action (may require human approval)",
	Args:  cobra.RangeArgs(1, 2),
	RunE: func(cmd *cobra.Command, args []string) error {
		payload := json.RawMessage(`{}`)
		if len(args) == 2 {
			if !json.Valid([]byte(args[1])) {
				return fmt.Errorf("payload is not valid JSON")
			}
			payload = json.RawMessage(args[1])
		}
		client, err := newAPIClient(cmd)
		if err != nil {
			return err
		}
		var out json.RawMessage
		if err := client.PostJSON(cmd.Context(), "/api/biz/run/"+args[0], payload, &out); err != nil {
			return err
		}
		return printRawJSON(out)
	},
}

func bizPath(p string) (string, error) {
	p = strings.TrimSpace(p)
	p = strings.TrimPrefix(p, "/api/biz")
	if !strings.HasPrefix(p, "/") || strings.Contains(p, "..") {
		return "", fmt.Errorf("path must start with / and stay under /api/biz")
	}
	return "/api/biz" + p, nil
}

func printRawJSON(raw json.RawMessage) error {
	var v any
	if err := json.Unmarshal(raw, &v); err != nil {
		_, err = os.Stdout.Write(raw)
		return err
	}
	enc := json.NewEncoder(os.Stdout)
	enc.SetIndent("", "  ")
	return enc.Encode(v)
}

func init() {
	bizCmd.AddCommand(bizGetCmd, bizRunCmd)
}
