"use client";

import { useEffect, useMemo, useState } from "react";
import { Controller, useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { z } from "zod";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import {
  fetchRepoConnection,
  connectRepo,
  fetchUserGithubRepos,
  triggerSync,
} from "@/lib/projects-api";
import { ApiError } from "@/lib/api";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Skeleton } from "@/components/ui/skeleton";
import { cn } from "@/lib/utils";
import { RefreshCwIcon } from "lucide-react";

const schema = z.object({
  full_name: z.string().min(1, "Select a repository"),
  branch: z.string().min(1, "Branch is required"),
});

type FormData = z.infer<typeof schema>;

interface RepoConnectionSectionProps {
  projectId: string;
}

function reposErrorMessage(err: unknown): string {
  if (err instanceof ApiError) {
    if (err.status === 400) {
      return "Sign out and sign in again so we can load your GitHub repositories.";
    }
    if (err.status === 502) {
      return "GitHub did not return your repository list. Try again in a moment.";
    }
  }
  return "Could not load your repositories.";
}

export function RepoConnectionSection({ projectId }: RepoConnectionSectionProps) {
  const [showForm, setShowForm] = useState(false);
  const [repoFilter, setRepoFilter] = useState("");
  const [syncError, setSyncError] = useState<string | null>(null);
  const [connectError, setConnectError] = useState<string | null>(null);
  const queryClient = useQueryClient();

  const { data: connection, isLoading } = useQuery({
    queryKey: ["repo-connection", projectId],
    queryFn: () => fetchRepoConnection(projectId),
  });

  const reposQuery = useQuery({
    queryKey: ["github-repos"],
    queryFn: fetchUserGithubRepos,
    enabled: showForm,
    staleTime: 60_000,
  });

  const filteredRepos = useMemo(() => {
    const repos = reposQuery.data;
    if (!repos) return [];
    const q = repoFilter.trim().toLowerCase();
    if (!q) return repos;
    return repos.filter((r) => r.full_name.toLowerCase().includes(q));
  }, [reposQuery.data, repoFilter]);

  const {
    register,
    control,
    handleSubmit,
    reset,
    setValue,
    watch,
    formState: { errors },
  } = useForm<FormData>({
    resolver: zodResolver(schema),
    defaultValues: { full_name: "", branch: "main" },
  });

  const fullName = watch("full_name");

  useEffect(() => {
    if (!reposQuery.data?.length || !fullName) return;
    const row = reposQuery.data.find((r) => r.full_name === fullName);
    if (row) {
      setValue("branch", row.default_branch || "main");
    }
  }, [fullName, reposQuery.data, setValue]);

  const connectMutation = useMutation({
    mutationFn: (data: FormData) => {
      const i = data.full_name.indexOf("/");
      const owner = data.full_name.slice(0, i);
      const repo = data.full_name.slice(i + 1);
      return connectRepo(projectId, {
        owner,
        repo,
        branch: data.branch.trim(),
      });
    },
    onMutate: () => setConnectError(null),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["repo-connection", projectId] });
      queryClient.invalidateQueries({ queryKey: ["releases", projectId] });
      setShowForm(false);
      setRepoFilter("");
      reset({ full_name: "", branch: "main" });
    },
    onError: (err) => {
      if (err instanceof ApiError && typeof err.body === "object" && err.body && "reason" in err.body) {
        setConnectError(String((err.body as { reason: unknown }).reason));
      } else {
        setConnectError("Could not connect that repository.");
      }
    },
  });

  const syncMutation = useMutation({
    mutationFn: () => triggerSync(projectId),
    onMutate: () => setSyncError(null),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["releases", projectId] });
      queryClient.invalidateQueries({ queryKey: ["repo-connection", projectId] });
    },
    onError: (err) => {
      if (err instanceof ApiError && err.status === 429) {
        setSyncError("Too many sync requests. Try again after a short wait.");
      } else {
        setSyncError("Sync failed. Try again.");
      }
    },
  });

  if (isLoading) {
    return <Skeleton className="h-48" />;
  }

  if (connection) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>Repository Connection</CardTitle>
          <CardDescription>
            {connection.webhook_id
              ? "Pushes to the default branch trigger a sync automatically."
              : "Manual sync only on your plan — use Sync Now after you push. Upgrade to Pro for GitHub webhooks."}
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <dl className="space-y-2 text-sm">
            <div>
              <dt className="text-muted-foreground">Repository</dt>
              <dd className="font-medium">
                {connection.repo_owner}/{connection.repo_name}
              </dd>
            </div>
            <div>
              <dt className="text-muted-foreground">Branch</dt>
              <dd className="font-medium">{connection.default_branch}</dd>
            </div>
            <div>
              <dt className="text-muted-foreground">Webhook</dt>
              <dd className="font-medium">
                {connection.webhook_id ? "Configured" : "Not configured (manual sync)"}
              </dd>
            </div>
          </dl>
          {syncError && (
            <p className="text-destructive text-sm">{syncError}</p>
          )}
          <Button
            onClick={() => syncMutation.mutate()}
            disabled={syncMutation.isPending}
          >
            <RefreshCwIcon
              className={`h-4 w-4 ${syncMutation.isPending ? "animate-spin" : ""}`}
            />
            {syncMutation.isPending ? "Syncing..." : "Sync Now"}
          </Button>
        </CardContent>
      </Card>
    );
  }

  if (showForm) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>Connect Repository</CardTitle>
          <CardDescription>
            Choose one of your GitHub repositories that contains SKILL.md files.
          </CardDescription>
        </CardHeader>
        <CardContent>
          {reposQuery.isPending && (
            <div className="space-y-3">
              <Skeleton className="h-8 w-full" />
              <Skeleton className="h-8 w-full" />
              <Skeleton className="h-8 w-32" />
            </div>
          )}
          {reposQuery.isError && (
            <p className="text-destructive mb-4 text-sm">
              {reposErrorMessage(reposQuery.error)}
            </p>
          )}
          {reposQuery.isSuccess && reposQuery.data.length === 0 && (
            <p className="text-muted-foreground mb-4 text-sm">
              No repositories found for this account. Create a repo on GitHub or check
              organization access, then try again.
            </p>
          )}
          {reposQuery.isSuccess && reposQuery.data.length > 0 && (
            <form
              onSubmit={handleSubmit((data) => connectMutation.mutate(data))}
              className="space-y-4"
            >
              <div className="space-y-2">
                <Label htmlFor="repo-filter">Search</Label>
                <Input
                  id="repo-filter"
                  value={repoFilter}
                  onChange={(e) => setRepoFilter(e.target.value)}
                  placeholder="Filter by name…"
                  autoComplete="off"
                />
              </div>
              <div className="space-y-2">
                <Label htmlFor="full_name">Repository</Label>
                <Controller
                  name="full_name"
                  control={control}
                  render={({ field }) => (
                    <Select
                      value={field.value ? field.value : null}
                      onValueChange={(v) => field.onChange(v ?? "")}
                    >
                      <SelectTrigger
                        id="full_name"
                        className={cn(
                          "w-full min-w-0",
                          errors.full_name &&
                            "border-destructive ring-destructive/20 dark:border-destructive/50"
                        )}
                        aria-invalid={errors.full_name ? true : undefined}
                      >
                        <SelectValue placeholder="Choose a repository…" />
                      </SelectTrigger>
                      <SelectContent>
                        {filteredRepos.map((r) => (
                          <SelectItem key={r.full_name} value={r.full_name}>
                            <span className="min-w-0 truncate">
                              {r.full_name}
                              {r.is_private ? " (private)" : ""}
                            </span>
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  )}
                />
                {errors.full_name && (
                  <p className="text-destructive text-sm">{errors.full_name.message}</p>
                )}
                {repoFilter && filteredRepos.length === 0 && (
                  <p className="text-muted-foreground text-sm">No matches.</p>
                )}
              </div>
              <div className="space-y-2">
                <Label htmlFor="branch">Default branch</Label>
                <Input
                  id="branch"
                  {...register("branch")}
                  placeholder="main"
                />
                {errors.branch && (
                  <p className="text-destructive text-sm">{errors.branch.message}</p>
                )}
                <p className="text-muted-foreground text-xs">
                  Usually filled from GitHub; change if your skills live on another branch.
                </p>
              </div>
              {connectError && (
                <p className="text-destructive text-sm">{connectError}</p>
              )}
              <div className="flex gap-2">
                <Button
                  type="button"
                  variant="outline"
                  onClick={() => {
                    setShowForm(false);
                    setRepoFilter("");
                    reset({ full_name: "", branch: "main" });
                    setConnectError(null);
                  }}
                >
                  Cancel
                </Button>
                <Button type="submit" disabled={connectMutation.isPending}>
                  {connectMutation.isPending ? "Connecting..." : "Connect"}
                </Button>
              </div>
            </form>
          )}
          {reposQuery.isSuccess && reposQuery.data.length === 0 && (
            <div className="flex gap-2 pt-2">
              <Button
                type="button"
                variant="outline"
                onClick={() => {
                  setShowForm(false);
                  setConnectError(null);
                }}
              >
                Back
              </Button>
            </div>
          )}
          {reposQuery.isError && (
            <div className="flex gap-2 pt-2">
              <Button type="button" variant="outline" onClick={() => setShowForm(false)}>
                Back
              </Button>
              <Button type="button" onClick={() => reposQuery.refetch()}>
                Retry
              </Button>
            </div>
          )}
        </CardContent>
      </Card>
    );
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>Repository Connection</CardTitle>
        <CardDescription>
          Connect a GitHub repository to sync SKILL.md files.
        </CardDescription>
      </CardHeader>
      <CardContent>
        <Button onClick={() => setShowForm(true)}>Connect Repository</Button>
      </CardContent>
    </Card>
  );
}
