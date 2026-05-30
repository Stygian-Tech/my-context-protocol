export function getApiKeyDisplayName(name: string | null | undefined) {
  return name && name.trim() ? name : "Unnamed key";
}
