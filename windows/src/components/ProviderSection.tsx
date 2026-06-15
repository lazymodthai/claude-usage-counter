import { useStore } from '../store'
import { UsageBar } from './UsageBar'
import { PROVIDER_LABELS, PROVIDER_ICONS, type ProviderID } from '../types'

const TINT: Record<ProviderID, string> = {
  claude: '#ff9f0a',
  codex: '#30d158',
  gemini: '#0a84ff',
}

const SESSION_ICON_COLOR: Record<ProviderID, string> = {
  claude: '#ff9f0a',
  codex: '#30d158',
  gemini: '#0a84ff',
}

interface Props {
  providerID: ProviderID
}

export function ProviderSection({ providerID }: Props) {
  const provider = useStore(s => s.providers[providerID])
  const { authState, sessionBar, weeklyBar, usingLocal } = provider
  const isConnected = authState === 'signed_in'
  const hasBars = isConnected || providerID === 'claude'
  const tint = TINT[providerID]

  return (
    <div className="provider-section">
      {/* Provider header */}
      <div className="provider-header">
        <span style={{ fontSize: 10, fontWeight: 600, color: tint }}>
          {PROVIDER_ICONS[providerID]}
        </span>
        <span className="provider-name">{PROVIDER_LABELS[providerID]}</span>

        {providerID === 'gemini' && isConnected && (
          <span className="badge">beta</span>
        )}
        {providerID === 'claude' && usingLocal && (
          <span className="badge">local estimate</span>
        )}
        {authState === 'expired' && (
          <span className="badge badge-yellow">session expired</span>
        )}

        <div className="spacer" />

        {!isConnected && (
          <button
            className="sign-in-btn"
            style={{ color: tint }}
            onClick={() => {/* TODO: OAuth login */}}
          >
            {authState === 'expired' ? 'Re-sign in' : 'Sign in'}
          </button>
        )}
      </div>

      {/* Usage bars */}
      {hasBars ? (
        <>
          {sessionBar && (
            <UsageBar
              label="Current Session"
              icon="🕐"
              iconColor={SESSION_ICON_COLOR[providerID]}
              vm={sessionBar}
            />
          )}
          {weeklyBar && (
            <UsageBar
              label="Weekly"
              icon="📅"
              iconColor="#33ade6"
              vm={weeklyBar}
            />
          )}
        </>
      ) : (
        <span className="not-connected">Not connected</span>
      )}
    </div>
  )
}
