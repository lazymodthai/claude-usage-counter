import { useStore } from '../store'
import { ALL_PROVIDERS, PROVIDER_LABELS, PROVIDER_ICONS } from '../types'

const IS_MAC = navigator.platform.toLowerCase().includes('mac')
const SHORTCUT_LABEL = IS_MAC ? '⌘⇧U' : 'Ctrl+Shift+U'

export function Settings() {
  const opacity = useStore(s => s.opacity)
  const alwaysOnTop = useStore(s => s.alwaysOnTop)
  const setOpacity = useStore(s => s.setOpacity)
  const setAlwaysOnTop = useStore(s => s.setAlwaysOnTop)
  const setShowSettings = useStore(s => s.setShowSettings)
  const visibleProviders = useStore(s => s.visibleProviders)
  const toggleProviderVisible = useStore(s => s.toggleProviderVisible)
  const sessionTokenLimit = useStore(s => s.sessionTokenLimit)
  const weeklyTokenLimit = useStore(s => s.weeklyTokenLimit)
  const refreshInterval = useStore(s => s.refreshInterval)
  const setSessionTokenLimit = useStore(s => s.setSessionTokenLimit)
  const setWeeklyTokenLimit = useStore(s => s.setWeeklyTokenLimit)
  const setRefreshInterval = useStore(s => s.setRefreshInterval)

  return (
    <div className="settings-overlay">
      <div className="settings-panel">
        <div className="settings-header">
          <span className="settings-title">Settings</span>
          <button className="icon-btn" onClick={() => setShowSettings(false)}>✕</button>
        </div>

        <div className="divider" />

        <div className="settings-body" style={{ maxHeight: 400, overflowY: 'auto' }}>
          {/* Visible Agents */}
          <div className="setting-col">
            <div className="setting-label">👁 Visible Agents</div>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 6, marginTop: 4 }}>
              {ALL_PROVIDERS.map(id => (
                <div key={id} className="setting-row" style={{ paddingLeft: 8 }}>
                  <div className="setting-label" style={{ fontSize: 11 }}>
                    <span style={{ display: 'inline-block', width: 16 }}>{PROVIDER_ICONS[id]}</span>
                    {PROVIDER_LABELS[id]}
                  </div>
                  <label className="toggle">
                    <input
                      type="checkbox"
                      checked={visibleProviders?.includes(id)}
                      onChange={() => toggleProviderVisible(id)}
                    />
                    <span className="toggle-track" />
                  </label>
                </div>
              ))}
            </div>
          </div>

          <div className="divider" />

          {/* Token Limits */}
          <div className="setting-col">
            <div className="setting-label">Claude Token Limits</div>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 8, marginTop: 4 }}>
              <div className="setting-row">
                <div className="setting-label" style={{ fontSize: 11 }}>Session Limit</div>
                <input 
                  type="number"
                  value={sessionTokenLimit || ''}
                  onChange={e => setSessionTokenLimit(Number(e.target.value))}
                  placeholder="0 = auto"
                  style={{ background: 'rgba(255,255,255,0.1)', color: 'white', border: 'none', borderRadius: 4, padding: '2px 6px', width: 90, fontSize: 11, textAlign: 'right' }}
                />
              </div>
              <div className="setting-row">
                <div className="setting-label" style={{ fontSize: 11 }}>Weekly Limit</div>
                <input 
                  type="number"
                  value={weeklyTokenLimit || ''}
                  onChange={e => setWeeklyTokenLimit(Number(e.target.value))}
                  placeholder="0 = auto"
                  style={{ background: 'rgba(255,255,255,0.1)', color: 'white', border: 'none', borderRadius: 4, padding: '2px 6px', width: 90, fontSize: 11, textAlign: 'right' }}
                />
              </div>
            </div>
          </div>

          <div className="divider" />

          {/* Refresh Interval */}
          <div className="setting-col">
            <div className="setting-label">Refresh Interval</div>
            <div className="setting-row" style={{ marginTop: 4 }}>
              <div className="setting-sub">Refresh every (seconds)</div>
              <input 
                type="number"
                min={30}
                value={refreshInterval}
                onChange={e => setRefreshInterval(Number(e.target.value))}
                style={{ background: 'rgba(255,255,255,0.1)', color: 'white', border: 'none', borderRadius: 4, padding: '2px 6px', width: 60, fontSize: 11, textAlign: 'right' }}
              />
            </div>
          </div>

          <div className="divider" />

          {/* Always on top */}
          <div className="setting-row">
            <div>
              <div className="setting-label">Always on Top</div>
              <div className="setting-sub">ลอยเหนือทุก window ตลอดเวลา</div>
            </div>
            <label className="toggle">
              <input
                type="checkbox"
                checked={alwaysOnTop}
                onChange={e => setAlwaysOnTop(e.target.checked)}
              />
              <span className="toggle-track" />
            </label>
          </div>

          <div className="divider" />

          {/* Opacity */}
          <div className="setting-col">
            <div className="setting-label">
              Opacity — {Math.round(opacity * 100)}%
            </div>
            <input
              type="range"
              min={0.3}
              max={1}
              step={0.05}
              value={opacity}
              onChange={e => setOpacity(parseFloat(e.target.value))}
              className="slider"
            />
          </div>

          <div className="divider" />

          {/* Keyboard shortcut info */}
          <div className="setting-col">
            <div className="setting-label">Keyboard Shortcut</div>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginTop: 4 }}>
              <kbd className="kbd">{SHORTCUT_LABEL}</kbd>
              <span className="setting-sub" style={{ margin: 0 }}>
                ซ่อน / แสดง overlay
              </span>
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}
