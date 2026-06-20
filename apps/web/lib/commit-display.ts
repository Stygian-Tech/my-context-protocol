/** Short label for commit / placeholder SHAs in release tables. */
export function shortCommitLabel(sha: string): string {
  const s = sha.trim();
  if (!s) return "—";
  if (s === "pending" || s === "unknown") return s;
  return s.length <= 7 ? s : s.slice(0, 7);
}
