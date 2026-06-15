import { create } from 'zustand'
import { invoke } from '@tauri-apps/api/core'
import { getCurrentWindow, PhysicalPosition, LogicalSize } from '@tauri-apps/api/window'
import type { ProviderID, ProviderState, AppState, ClaudeLocalUsage } from './types'
import { formatTokens, formatCountdown, formatResetLabel } from './utils'

const FULL_HEIGHT = 500
const COMPACT_HEIGHT = 44

interface Store extends AppState {
  showSettings: boolean
  refreshAll: () => Promise<void>
  setMenubarSource: (id: ProviderID) => void
  setOpacity: (v: number) => void
  setAlwaysOnTop: (v: boolean) => void
  setShowSettings: (v: boolean) => void
  setCompact: (v: boolean) => Promise<void>
  hideWindow: () => Promise<void>
  initWindow: () => Promise<void>
}

const defaultProvider = (): ProviderState => ({
  authState: 'signed_out',
  sessionBar: null,
  weeklyBar: null,
  fetchedAt: null,
  usingLocal: false,
})

function mapClaudeUsage(u: ClaudeLocalUsage): ProviderState {
  return {
    authState: 'signed_in',
    usingLocal: u.is_local,
    fetchedAt: new Date(u.fetched_at),
    sessionBar: {
      fraction: u.session_fraction,
      usedText: formatTokens(u.session_tokens),
      limitText: formatTokens(u.session_limit),
      resetLabel: u.session_active && u.session_reset_secs > 0
        ? formatCountdown(u.session_reset_secs)
        : '',
      isActive: u.session_active,
    },
    weeklyBar: {
      fraction: u.weekly_fraction,
      usedText: formatTokens(u.weekly_tokens),
      limitText: formatTokens(u.weekly_limit),
      resetLabel: formatResetLabel(u.weekly_reset_secs),
      isActive: true,
    },
  }
}

export const useStore = create<Store>((set, get) => ({
  providers: {
    claude: defaultProvider(),
    codex: defaultProvider(),
    gemini: defaultProvider(),
  },
  menubarSource: 'claude',
  isLoading: false,
  opacity: 0.95,
  alwaysOnTop: true,
  compact: false,
  showSettings: false,

  refreshAll: async () => {
    set({ isLoading: true })
    try {
      const usage = await invoke<ClaudeLocalUsage>('get_claude_local_usage')
      set(state => ({
        providers: { ...state.providers, claude: mapClaudeUsage(usage) },
      }))
    } catch (e) {
      console.error('Claude local usage error:', e)
    } finally {
      set({ isLoading: false })
    }
  },

  setMenubarSource: id => set({ menubarSource: id }),

  setOpacity: v => set({ opacity: v }),

  setAlwaysOnTop: async v => {
    set({ alwaysOnTop: v })
    try { await getCurrentWindow().setAlwaysOnTop(v) } catch {}
  },

  setShowSettings: v => set({ showSettings: v }),

  setCompact: async v => {
    set({ compact: v })
    try {
      const height = v ? COMPACT_HEIGHT : FULL_HEIGHT
      await getCurrentWindow().setSize(new LogicalSize(320, height))
    } catch {}
  },

  hideWindow: async () => {
    try { await getCurrentWindow().hide() } catch {}
  },

  initWindow: async () => {
    try {
      const win = getCurrentWindow()

      // Restore saved position
      const saved = localStorage.getItem('windowPos')
      if (saved) {
        const { x, y } = JSON.parse(saved) as { x: number; y: number }
        await win.setPosition(new PhysicalPosition(x, y))
      }

      // Apply always-on-top
      await win.setAlwaysOnTop(get().alwaysOnTop)

      // Restore compact mode
      const savedCompact = localStorage.getItem('compact') === 'true'
      if (savedCompact) {
        set({ compact: true })
        await win.setSize(new LogicalSize(320, COMPACT_HEIGHT))
      }

      // Save position whenever window moves
      await win.listen('tauri://move', async () => {
        const pos = await win.outerPosition()
        localStorage.setItem('windowPos', JSON.stringify({ x: pos.x, y: pos.y }))
      })

      // Listen for tray toggle-compact event
      await win.listen('toggle-compact', () => {
        const next = !useStore.getState().compact
        useStore.getState().setCompact(next)
        localStorage.setItem('compact', String(next))
      })

      // Listen for tray show event (restores from hide)
      await win.listen('tauri://focus', () => {
        // nothing needed — Tauri shows window automatically
      })
    } catch {}
  },
}))
