import { useStore } from '../store'

const IS_MAC = navigator.platform.toLowerCase().includes('mac')
const SHORTCUT_LABEL = IS_MAC ? '⌘⇧U' : 'Ctrl+Shift+U'

export function Settings() {
  const opacity = useStore(s => s.opacity)
  const alwaysOnTop = useStore(s => s.alwaysOnTop)
  const setOpacity = useStore(s => s.setOpacity)
  const setAlwaysOnTop = useStore(s => s.setAlwaysOnTop)
  const setShowSettings = useStore(s => s.setShowSettings)

  return (
    <div className="settings-overlay">
      <div className="settings-panel">
        <div className="settings-header">
          <span className="settings-title">Settings</span>
          <button className="icon-btn" onClick={() => setShowSettings(false)}>✕</button>
        </div>

        <div className="divider" />

        <div className="settings-body">
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
