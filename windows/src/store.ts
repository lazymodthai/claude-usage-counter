import { create } from 'zustand'
import { invoke } from '@tauri-apps/api/core'
import { listen } from '@tauri-apps/api/event'
import { getCurrentWindow, PhysicalPosition, LogicalSize, currentMonitor } from '@tauri-apps/api/window'
import type { ProviderID, ProviderState, AppState, AntigravityUsage, ProviderUsageResult, ExpandDir, ExpandSetting } from './types'
import { ALL_PROVIDERS } from './types'
import { formatCountdown, formatResetLabel } from './utils'

const COMPACT_HEIGHT = 44

// The full size the overlay expands to (validated saved size, or layout default).
function targetFullSize(twoCol: boolean): { w: number; h: number } {
  let w = twoCol ? 640 : 320
  let h = 500
  const saved = localStorage.getItem('windowSize')
  if (saved) {
    try {
      const s = JSON.parse(saved) as { w: number; h: number }
      if (s.w >= 280 && s.h >= 200) { w = s.w; h = s.h }
    } catch {}
  }
  return { w, h }
}

// Pick the expand direction from where the window sits on its monitor: grow into
// whichever edge has room (vertical preferred, since height grows the most).
function computeAutoDir(
  pos: { x: number; y: number },
  size: { width: number; height: number },
  mon: { position: { x: number; y: number }; size: { width: number; height: number }; scaleFactor: number },
  fullWp: number,
  fullHp: number,
): ExpandDir {
  const taskbar = Math.round(48 * (mon.scaleFactor || 1))
  const needH = Math.max(0, fullHp - size.height)
  const below = (mon.position.y + mon.size.height - taskbar) - (pos.y + size.height)
  const above = pos.y - mon.position.y
  if (below >= needH) return 'down'
  if (above >= needH) return 'up'
  const needW = Math.max(0, fullWp - size.width)
  const right = (mon.position.x + mon.size.width) - (pos.x + size.width)
  const left = pos.x - mon.position.x
  if (needW > 0 && right >= needW) return 'right'
  if (needW > 0 && left >= needW) return 'left'
  return below >= above ? 'down' : 'up'
}

// Keep the window fully on its monitor (minus the taskbar) so an expand can
// never push it off-screen beyond recovery.
function clampToMonitor(
  x: number, y: number, wp: number, hp: number,
  mon: { position: { x: number; y: number }; size: { width: number; height: number }; scaleFactor: number },
): WinPoint {
  const taskbar = Math.round(48 * (mon.scaleFactor || 1))
  const minX = mon.position.x
  const minY = mon.position.y
  const maxX = mon.position.x + mon.size.width - wp
  const maxY = mon.position.y + mon.size.height - taskbar - hp
  return {
    x: Math.round(Math.max(minX, Math.min(x, maxX))),
    y: Math.round(Math.max(minY, Math.min(y, maxY))),
  }
}

// Compute the new top-left (physical px) so the window grows toward `dir`,
// keeping the opposite edge pinned (and centering the perpendicular axis).
type WinPoint = { x: number; y: number }
function anchoredPos(
  pos: WinPoint,
  oldSize: { width: number; height: number },
  newWp: number,
  newHp: number,
  dir: ExpandDir,
): WinPoint {
  const cx = pos.x + oldSize.width / 2
  const cy = pos.y + oldSize.height / 2
  switch (dir) {
    case 'up':    return { x: Math.round(cx - newWp / 2), y: Math.round(pos.y + oldSize.height - newHp) }
    case 'left':  return { x: Math.round(pos.x + oldSize.width - newWp), y: Math.round(cy - newHp / 2) }
    case 'right': return { x: pos.x, y: Math.round(cy - newHp / 2) }
    case 'down':
    default:      return { x: Math.round(cx - newWp / 2), y: pos.y }
  }
}

interface Store extends AppState {
  showSettings: boolean
  visibleProviders: ProviderID[]
  sessionTokenLimit: number
  weeklyTokenLimit: number
  refreshInterval: number
  autoDim: boolean
  petIcon: string
  expandDirection: ExpandSetting
  autoResolved: ExpandDir

  refreshAll: () => Promise<void>
  loadProviderAuthStates: () => Promise<void>
  openLoginWindow: (provider: ProviderID) => Promise<void>
  signOutProvider: (provider: ProviderID) => Promise<void>
  setMenubarSource: (id: ProviderID) => void
  setOpacity: (v: number) => void
  setAutoDim: (v: boolean) => void
  setAlwaysOnTop: (v: boolean) => void
  setShowSettings: (v: boolean) => void
  setCompact: (v: boolean) => Promise<void>
  hideWindow: () => Promise<void>
  initWindow: () => Promise<void>

  setVisibleProviders: (ids: ProviderID[]) => void
  toggleProviderVisible: (id: ProviderID) => void
  setSessionTokenLimit: (v: number) => void
  setWeeklyTokenLimit: (v: number) => void
  setRefreshInterval: (v: number) => void
  setPetIcon: (v: string) => void
  cycleExpandDirection: () => void
  refreshAutoDir: () => Promise<void>
}

const defaultProvider = (): ProviderState => ({
  authState: 'signed_out',
  sessionBar: null,
  weeklyBar: null,
  quotaLanes: [],
  fetchedAt: null,
  usingLocal: false,
})

function mapProviderUsage(u: ProviderUsageResult): ProviderState {
  const pctToFraction = (pct: number | null) => pct != null ? pct / 100 : 0
  return {
    authState: u.is_auth_expired ? 'expired' : 'signed_in',
    usingLocal: false,
    fetchedAt: new Date(u.fetched_at),
    quotaLanes: u.quota_lanes.map(l => ({
      id: l.id,
      label: l.label,
      group: l.group,
      pct: l.pct,
      resetText: l.reset_text,
    })),
    sessionBar: u.session_pct != null ? {
      fraction: pctToFraction(u.session_pct),
      usedText: `${u.session_pct.toFixed(1)}%`,
      limitText: '100%',
      resetLabel: u.session_reset_secs != null ? formatCountdown(u.session_reset_secs) : '',
      isActive: true,
    } : null,
    weeklyBar: u.weekly_pct != null ? {
      fraction: pctToFraction(u.weekly_pct),
      usedText: `${u.weekly_pct.toFixed(1)}%`,
      limitText: '100%',
      resetLabel: u.weekly_reset_secs != null ? formatResetLabel(u.weekly_reset_secs) : '',
      isActive: true,
    } : null,
  }
}

export const useStore = create<Store>((set, get) => ({
  providers: {
    claude: defaultProvider(),
    codex: defaultProvider(),
    gemini: defaultProvider(),
    antigravity: defaultProvider(),
  },
  menubarSource: (localStorage.getItem('menubarSource') as ProviderID) || 'claude',
  isLoading: false,
  opacity: (() => {
    const v = Number(localStorage.getItem('idleOpacity'))
    return v > 0 ? v : 0.4
  })(),
  autoDim: localStorage.getItem('autoDim') !== 'false',
  alwaysOnTop: true,
  compact: false,
  showSettings: false,
  visibleProviders: (() => {
    try {
      const stored = localStorage.getItem('visibleProviders')
      return stored ? JSON.parse(stored) : ALL_PROVIDERS
    } catch {
      return ALL_PROVIDERS
    }
  })(),
  sessionTokenLimit: Number(localStorage.getItem('sessionTokenLimit')) || 0,
  weeklyTokenLimit: Number(localStorage.getItem('weeklyTokenLimit')) || 0,
  refreshInterval: Number(localStorage.getItem('refreshInterval')) || 60,
  // Off by default — user opts in by setting an emoji in Settings.
  petIcon: localStorage.getItem('petIcon') ?? '',
  expandDirection: (localStorage.getItem('expandDirection') as ExpandSetting) || 'auto',
  autoResolved: 'down',

  loadProviderAuthStates: async () => {
    for (const provider of ['claude', 'codex', 'gemini'] as ProviderID[]) {
      try {
        const authState = await invoke<string>('get_provider_auth_state', { provider })
        set(state => ({
          providers: {
            ...state.providers,
            [provider]: {
              ...state.providers[provider],
              authState: authState as 'signed_in' | 'signed_out' | 'expired',
            },
          },
        }))
      } catch (e) {
        // ignore — stays signed_out
      }
    }
  },

  openLoginWindow: async (provider: ProviderID) => {
    await invoke('open_login_window', { provider })
  },

  signOutProvider: async (provider: ProviderID) => {
    await invoke('sign_out_provider', { provider })
    set(state => ({
      providers: {
        ...state.providers,
        [provider]: { ...state.providers[provider], authState: 'signed_out', sessionBar: null, weeklyBar: null, quotaLanes: [] },
      },
    }))
  },

  refreshAll: async () => {
    set({ isLoading: true })

    // Claude: official claude.ai API only (requires login) — never a local estimate.
    const claudeAuth = get().providers.claude.authState
    if (claudeAuth === 'signed_in' || claudeAuth === 'expired') {
      try {
        const result = await invoke<ProviderUsageResult | null>('get_claude_usage')
        if (result) {
          set(state => ({ providers: { ...state.providers, claude: mapProviderUsage(result) } }))
        }
      } catch (e) {
        console.error('Claude usage error:', e)
      }
    }

    // Fetch Codex usage if signed in
    const codexAuth = get().providers.codex.authState
    if (codexAuth === 'signed_in' || codexAuth === 'expired') {
      try {
        const result = await invoke<ProviderUsageResult | null>('get_codex_usage')
        if (result) {
          const mapped = mapProviderUsage(result)
          set(state => ({ providers: { ...state.providers, codex: mapped } }))
        }
      } catch (e) {
        console.error('Codex usage error:', e)
      }
    }

    // Fetch Gemini usage if signed in
    const geminiAuth = get().providers.gemini.authState
    if (geminiAuth === 'signed_in' || geminiAuth === 'expired') {
      try {
        const result = await invoke<ProviderUsageResult | null>('get_gemini_usage')
        if (result) {
          const mapped = mapProviderUsage(result)
          set(state => ({ providers: { ...state.providers, gemini: mapped } }))
        }
      } catch (e) {
        console.error('Gemini usage error:', e)
      }
    }

    try {
      const antiUsage = await invoke<AntigravityUsage | null>('get_antigravity_usage')
      if (antiUsage) {
        set(state => ({
          providers: {
            ...state.providers,
            antigravity: {
              authState: 'signed_in',
              sessionBar: null,
              weeklyBar: null,
              quotaLanes: antiUsage.lanes.map(l => ({
                id: l.id,
                label: l.label,
                group: l.group,
                pct: l.pct,
                resetText: l.reset_text,
              })),
              fetchedAt: new Date(antiUsage.fetched_at),
              usingLocal: true,
            }
          }
        }))
      } else {
        set(state => ({
          providers: {
            ...state.providers,
            antigravity: {
              ...state.providers.antigravity,
              authState: 'signed_out',
            }
          }
        }))
      }
    } catch (e) {
      console.error('Antigravity usage error:', e)
    } finally {
      set({ isLoading: false })

      // Update tray title
      const state = get()
      const provider = state.providers[state.menubarSource]
      const fraction = provider.sessionBar?.fraction ?? 0
      const pct = Math.round(fraction * 100)
      try {
        await invoke('update_tray_title', { title: `AI Usage — ${pct}%` })
      } catch (e) {
        // ignore
      }
    }
  },

  setVisibleProviders: (ids) => {
    if (ids.length === 0) return
    set({ visibleProviders: ids })
    localStorage.setItem('visibleProviders', JSON.stringify(ids))
  },
  toggleProviderVisible: (id) => {
    const current = get().visibleProviders
    if (current.includes(id)) {
      if (current.length > 1) {
        const next = current.filter(x => x !== id)
        set({ visibleProviders: next })
        localStorage.setItem('visibleProviders', JSON.stringify(next))
      }
    } else {
      const next = [...current, id]
      set({ visibleProviders: next })
      localStorage.setItem('visibleProviders', JSON.stringify(next))
    }
  },
  setSessionTokenLimit: (v) => {
    set({ sessionTokenLimit: v })
    localStorage.setItem('sessionTokenLimit', String(v))
  },
  setWeeklyTokenLimit: (v) => {
    set({ weeklyTokenLimit: v })
    localStorage.setItem('weeklyTokenLimit', String(v))
  },
  setRefreshInterval: (v) => {
    const valid = Math.max(30, v)
    set({ refreshInterval: valid })
    localStorage.setItem('refreshInterval', String(valid))
  },
  setPetIcon: (v) => {
    set({ petIcon: v })
    localStorage.setItem('petIcon', v)
  },
  cycleExpandDirection: () => {
    const order: ExpandSetting[] = ['auto', 'down', 'up', 'left', 'right']
    const next = order[(order.indexOf(get().expandDirection) + 1) % order.length]
    set({ expandDirection: next })
    localStorage.setItem('expandDirection', next)
    if (next === 'auto') get().refreshAutoDir()
  },

  // When in auto mode, recompute which way to grow from the current screen spot.
  refreshAutoDir: async () => {
    if (get().expandDirection !== 'auto') return
    try {
      const win = getCurrentWindow()
      const sf = await win.scaleFactor()
      const pos = await win.outerPosition()
      const size = await win.outerSize()
      const mon = await currentMonitor()
      if (!mon) return
      const twoCol =
        get().visibleProviders.includes('antigravity') &&
        get().visibleProviders.some(id => id !== 'antigravity')
      const t = targetFullSize(twoCol)
      const dir = computeAutoDir(pos, size, mon, Math.round(t.w * sf), Math.round(t.h * sf))
      if (dir !== get().autoResolved) set({ autoResolved: dir })
    } catch {}
  },

  setMenubarSource: id => {
    set({ menubarSource: id })
    localStorage.setItem('menubarSource', id)
  },

  setOpacity: v => {
    set({ opacity: v })
    localStorage.setItem('idleOpacity', String(v))
  },

  setAutoDim: v => {
    set({ autoDim: v })
    localStorage.setItem('autoDim', String(v))
  },

  setAlwaysOnTop: async v => {
    set({ alwaysOnTop: v })
    try { await getCurrentWindow().setAlwaysOnTop(v) } catch {}
  },

  setShowSettings: v => set({ showSettings: v }),

  setCompact: async v => {
    const win = getCurrentWindow()
    const setting = get().expandDirection
    try {
      const sf = await win.scaleFactor()
      const pos = await win.outerPosition()
      const oldSize = await win.outerSize()
      const mon = await currentMonitor()

      const twoCol =
        get().visibleProviders.includes('antigravity') &&
        get().visibleProviders.some(id => id !== 'antigravity')

      let w: number
      let h: number
      if (v) {
        // Collapse: remember the current full size first (ignore tiny values).
        const cur = (await win.innerSize()).toLogical(sf)
        if (cur.height > 120) {
          localStorage.setItem('windowSize', JSON.stringify({ w: Math.round(cur.width), h: Math.round(cur.height) }))
        }
        w = 320
        h = COMPACT_HEIGHT
      } else {
        // Expand to the saved full size (validated), or a sensible default.
        const t = targetFullSize(twoCol)
        w = t.w
        h = t.h
      }

      const newWp = Math.round(w * sf)
      const newHp = Math.round(h * sf)

      // Resolve the grow direction. In auto: compute fresh from the screen
      // position when expanding; reuse the last resolved value when collapsing
      // so the pill returns to where it came from.
      let dir: ExpandDir
      if (setting === 'auto') {
        if (v) {
          dir = get().autoResolved
        } else {
          dir = mon ? computeAutoDir(pos, oldSize, mon, newWp, newHp) : 'down'
          set({ autoResolved: dir })
        }
      } else {
        dir = setting
      }

      // Pin the opposite edge so the window grows toward `dir`, then clamp to the
      // monitor so it can never slip off-screen (recoverable in every case).
      let np = anchoredPos(pos, oldSize, newWp, newHp, dir)
      if (mon) np = clampToMonitor(np.x, np.y, newWp, newHp, mon)
      set({ compact: v })
      localStorage.setItem('compact', String(v))
      await win.setSize(new LogicalSize(w, h))
      await win.setPosition(new PhysicalPosition(np.x, np.y))
    } catch {
      set({ compact: v })
      localStorage.setItem('compact', String(v))
    }
  },

  hideWindow: async () => {
    try { await getCurrentWindow().hide() } catch {}
  },

  initWindow: async () => {
    // Load Codex/Gemini auth states from disk before showing UI
    await useStore.getState().loadProviderAuthStates()

    try {
      const win = getCurrentWindow()

      // Restore saved position, or place bottom-right on first launch
      const saved = localStorage.getItem('windowPos')
      if (saved) {
        const { x, y } = JSON.parse(saved) as { x: number; y: number }
        await win.setPosition(new PhysicalPosition(x, y))
      } else {
        // First launch: place overlay at bottom-right near system tray
        try {
          const monitor = await currentMonitor()
          if (monitor) {
            const { width, height } = monitor.size
            const scaleFactor = monitor.scaleFactor
            // overlay is 320×500 logical px, convert to physical
            const overlayW = Math.round(320 * scaleFactor)
            const overlayH = Math.round(500 * scaleFactor)
            const margin = Math.round(16 * scaleFactor)
            const taskbarH = Math.round(48 * scaleFactor)
            await win.setPosition(new PhysicalPosition(
              width - overlayW - margin,
              height - overlayH - taskbarH - margin,
            ))
          }
        } catch {}
        // Show first-launch notification pointing to tray icon
        await invoke('show_first_launch_tip').catch(() => {})
      }

      // Apply always-on-top
      await win.setAlwaysOnTop(get().alwaysOnTop)

      // Restore compact mode
      const savedCompact = localStorage.getItem('compact') === 'true'
      if (savedCompact) {
        set({ compact: true })
        await win.setSize(new LogicalSize(320, COMPACT_HEIGHT))
      }

      // Recover a window that ended up off-screen (e.g. a previously saved
      // off-screen position): pull it back fully onto the monitor.
      try {
        const mon = await currentMonitor()
        if (mon) {
          const size = await win.outerSize()
          const cur = await win.outerPosition()
          const np = clampToMonitor(cur.x, cur.y, size.width, size.height, mon)
          if (np.x !== cur.x || np.y !== cur.y) {
            await win.setPosition(new PhysicalPosition(np.x, np.y))
          }
        }
      } catch {}

      // Save position whenever window moves, and (throttled) re-pick the auto
      // grow direction so the arrow reflects where it'll expand from here.
      let lastAutoTick = 0
      await win.listen('tauri://move', async () => {
        const pos = await win.outerPosition()
        localStorage.setItem('windowPos', JSON.stringify({ x: pos.x, y: pos.y }))
        const now = Date.now()
        if (now - lastAutoTick > 250) {
          lastAutoTick = now
          get().refreshAutoDir()
        }
      })

      // Save size whenever the user resizes (ignore the compact pill and any
      // transient tiny sizes so an expand can always restore a usable size).
      await win.listen('tauri://resize', async () => {
        if (get().compact) return
        try {
          const sf = await win.scaleFactor()
          const size = (await win.innerSize()).toLogical(sf)
          if (size.height < 120) return
          localStorage.setItem('windowSize', JSON.stringify({
            w: Math.round(size.width),
            h: Math.round(size.height),
          }))
        } catch {}
      })

      // Listen for tray toggle-compact event
      await win.listen('toggle-compact', () => {
        const next = !useStore.getState().compact
        useStore.getState().setCompact(next)
        localStorage.setItem('compact', String(next))
      })

      // Keep the overlay above the taskbar and other windows. Windows can drop
      // a topmost window behind the (also-topmost) taskbar when another app
      // minimizes/restores, so re-assert topmost on focus and on a short timer.
      const reassertTopmost = () => {
        if (get().alwaysOnTop) win.setAlwaysOnTop(true).catch(() => {})
      }
      await win.listen('tauri://focus', reassertTopmost)
      setInterval(reassertTopmost, 2000)

      // Refresh auth state when a provider login window closes
      await listen<string>('auth-state-changed', (event) => {
        const provider = event.payload as ProviderID
        set(state => ({
          providers: {
            ...state.providers,
            [provider]: { ...state.providers[provider], authState: 'signed_in' },
          },
        }))
        // Immediately fetch usage for the newly logged-in provider
        useStore.getState().refreshAll()
      })

      // Seed the auto grow-direction arrow from the restored position.
      get().refreshAutoDir()
    } catch {}
  },
}))
