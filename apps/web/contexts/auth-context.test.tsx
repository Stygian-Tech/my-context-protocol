/** @vitest-environment jsdom */
import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { AuthProvider, useAuth } from "./auth-context";
import { getCurrentUser, logout } from "@/lib/auth";
import type { User } from "@/lib/types";

const replace = vi.hoisted(() => vi.fn());
vi.mock("next/navigation", () => ({ useRouter: () => ({ replace }) }));
vi.mock("@/lib/auth", () => ({ getCurrentUser: vi.fn(), logout: vi.fn(), getGitHubLoginUrl: vi.fn() }));
const oldUser = { id: "old", login: "old-user", plan: "free" } as User;
let auth: ReturnType<typeof useAuth>;
function Consumer() { auth = useAuth(); return <span>{auth.user?.login ?? "signed-out"}</span>; }

describe("AuthProvider account changes", () => {
  let host: HTMLDivElement;
  let root: Root;
  let client: QueryClient;
  beforeEach(() => {
    vi.resetAllMocks();
    client = new QueryClient();
    host = document.createElement("div"); document.body.appendChild(host); root = createRoot(host);
    vi.mocked(getCurrentUser).mockResolvedValue(oldUser);
    vi.mocked(logout).mockResolvedValue(undefined);
  });
  afterEach(async () => { await act(async () => root.unmount()); host.remove(); client.clear(); });
  async function render() {
    await act(async () => root.render(<QueryClientProvider client={client}><AuthProvider><Consumer /></AuthProvider></QueryClientProvider>));
  }

  it("does not restore an old account when an auth request finishes after logout", async () => {
    await render();
    let resolve!: (user: User) => void;
    vi.mocked(getCurrentUser).mockReturnValueOnce(new Promise<User>((done) => { resolve = done; }));
    let pending!: Promise<void>;
    await act(async () => { pending = auth.refreshUser(); });
    client.setQueryData(["projects"], ["old-private-project"]);
    await act(async () => { await auth.logout(); });
    await act(async () => { resolve(oldUser); await pending; });
    expect(host.textContent).toBe("signed-out");
    expect(client.getQueryData(["projects"])).toBeUndefined();
    expect(replace).toHaveBeenCalledWith("/login?select_account=1");
    expect(getCurrentUser).toHaveBeenCalledTimes(2);
  });

  it("clears the old user when a refresh reports an expired session", async () => {
    await render();
    vi.mocked(getCurrentUser).mockResolvedValueOnce(null);
    await act(async () => { await auth.refreshUser(); });
    expect(host.textContent).toBe("signed-out");
  });

  it("keeps the account when the server rejects logout", async () => {
    await render();
    vi.mocked(logout).mockRejectedValueOnce(new Error("unavailable"));
    await act(async () => { await expect(auth.logout()).rejects.toThrow("unavailable"); });
    expect(host.textContent).toBe("old-user");
    expect(replace).not.toHaveBeenCalled();
  });
});
