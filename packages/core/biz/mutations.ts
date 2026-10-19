import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useWorkspaceId } from "../hooks";
import { issueKeys } from "../issues/queries";
import { bizApi } from "./api";
import { bizKeys } from "./queries";

/**
 * Runs a business action. Awaits the server (no optimistic writes: actions
 * can be refused by policy or turned into an approval) and refreshes the
 * business projection plus issues/projects, which actions may create.
 */
export function useBizRun() {
  const qc = useQueryClient();
  const wsId = useWorkspaceId();
  return useMutation({
    mutationFn: ({ action, payload }: { action: string; payload: unknown }) => bizApi.run(action, payload),
    onSettled: () => {
      qc.invalidateQueries({ queryKey: bizKeys.all(wsId) });
      qc.invalidateQueries({ queryKey: issueKeys.all(wsId) });
      qc.invalidateQueries({ queryKey: ["projects", wsId] });
    },
  });
}

export function useBizDecide() {
  const qc = useQueryClient();
  const wsId = useWorkspaceId();
  return useMutation({
    mutationFn: ({ id, approve, reason }: { id: string; approve: boolean; reason: string }) => bizApi.decide(id, approve, reason),
    onSettled: () => {
      qc.invalidateQueries({ queryKey: bizKeys.all(wsId) });
      qc.invalidateQueries({ queryKey: issueKeys.all(wsId) });
    },
  });
}

export function useBizFolder() {
  const qc = useQueryClient();
  const wsId = useWorkspaceId();
  return useMutation({
    mutationFn: async ({ op }: { op: "export" | "preview" | "apply" }) =>
      op === "export" ? bizApi.folderExport() : bizApi.folderRebuild(op === "apply"),
    onSettled: () => qc.invalidateQueries({ queryKey: bizKeys.all(wsId) }),
  });
}
