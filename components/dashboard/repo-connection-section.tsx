"use client";

import { useState } from "react";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { z } from "zod";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import {
  fetchRepoConnection,
  connectRepo,
  triggerSync,
} from "@/lib/projects-api";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Skeleton } from "@/components/ui/skeleton";
import { RefreshCwIcon } from "lucide-react";

const schema = z.object({
  owner: z.string().min(1, "Owner is required"),
  repo: z.string().min(1, "Repo is required"),
  branch: z.string().min(1, "Branch is required"),
});

type FormData = z.infer<typeof schema>;

interface RepoConnectionSectionProps {
  projectId: string;
}

export function RepoConnectionSection({ projectId }: RepoConnectionSectionProps) {
  const [showForm, setShowForm] = useState(false);
  const queryClient = useQueryClient();

  const { data: connection, isLoading } = useQuery({
    queryKey: ["repo-connection", projectId],
    queryFn: () => fetchRepoConnection(projectId),
  });

  const {
    register,
    handleSubmit,
    reset,
    formState: { errors },
  } = useForm<FormData>({
    resolver: zodResolver(schema),
    defaultValues: { owner: "", repo: "", branch: "main" } as FormData,
  });

  const connectMutation = useMutation({
    mutationFn: (data: FormData) => connectRepo(projectId, data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["repo-connection", projectId] });
      queryClient.invalidateQueries({ queryKey: ["releases", projectId] });
      setShowForm(false);
      reset();
    },
  });

  const syncMutation = useMutation({
    mutationFn: () => triggerSync(projectId),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["releases", projectId] });
      queryClient.invalidateQueries({ queryKey: ["repo-connection", projectId] });
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
            Connected to GitHub. Push to the repo to trigger updates.
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
            {connection.webhook_id && (
              <div>
                <dt className="text-muted-foreground">Webhook</dt>
                <dd className="font-medium">Configured</dd>
              </div>
            )}
          </dl>
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
            Connect a GitHub repository containing SKILL.md files.
          </CardDescription>
        </CardHeader>
        <CardContent>
          <form
            onSubmit={handleSubmit((data) => connectMutation.mutate(data))}
            className="space-y-4"
          >
            <div className="space-y-2">
              <Label htmlFor="owner">Owner</Label>
              <Input
                id="owner"
                {...register("owner")}
                placeholder="owner"
              />
              {errors.owner && (
                <p className="text-destructive text-sm">{errors.owner.message}</p>
              )}
            </div>
            <div className="space-y-2">
              <Label htmlFor="repo">Repository</Label>
              <Input
                id="repo"
                {...register("repo")}
                placeholder="repo-name"
              />
              {errors.repo && (
                <p className="text-destructive text-sm">{errors.repo.message}</p>
              )}
            </div>
            <div className="space-y-2">
              <Label htmlFor="branch">Branch</Label>
              <Input
                id="branch"
                {...register("branch")}
                placeholder="main"
              />
              {errors.branch && (
                <p className="text-destructive text-sm">{errors.branch.message}</p>
              )}
            </div>
            <div className="flex gap-2">
              <Button
                type="button"
                variant="outline"
                onClick={() => setShowForm(false)}
              >
                Cancel
              </Button>
              <Button type="submit" disabled={connectMutation.isPending}>
                {connectMutation.isPending ? "Connecting..." : "Connect"}
              </Button>
            </div>
          </form>
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
