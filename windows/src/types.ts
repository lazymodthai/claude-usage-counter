export type ProviderID = 'claude' | 'codex' | 'gemini'
export type AuthState = 'signed_in' | 'signed_out' | 'expired'

export interface UsageBarVM {
  fraction: number
  usedText: string
  limitText: string
  resetLabel: string
  isActive: boolean
}

export interface ProviderState {
  authState: AuthState
  sessionBar: UsageBarVM | null
  weeklyBar: UsageBarVM | null
  fetchedAt: Date | null
  usingLocal: boolean
}

export interface AppState {
  providers: Record<ProviderID, ProviderState>
  menubarSource: ProviderID
  isLoading: boolean
  opacity: number
  alwaysOnTop: boolean
  compact: boolean
}

export const ALL_PROVIDERS: ProviderID[] = ['claude', 'codex', 'gemini']

export const PROVIDER_LABELS: Record<ProviderID, string> = {
  claude: 'Claude',
  codex: 'Codex',
  gemini: 'Gemini',
}

export const PROVIDER_ICONS: Record<ProviderID, string> = {
  claude: '⚡',
  codex: '</>',
  gemini: '✦',
}

// Rust response shape from get_claude_local_usage
export interface ClaudeLocalUsage {
  session_tokens: number
  session_limit: number
  session_fraction: number
  session_reset_secs: number
  session_active: boolean
  weekly_tokens: number
  weekly_limit: number
  weekly_fraction: number
  weekly_reset_secs: number
  is_local: boolean
  fetched_at: string
}
