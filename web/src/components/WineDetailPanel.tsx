import { useEffect } from 'react';
import type { WineRecord } from '../types/wine';
import { absoluteImageUrl } from '../api/client';

interface WineDetailPanelProps {
  wine: WineRecord;
  onClose: () => void;
  onVerify: (verified: boolean) => void;
  onDelete: () => void;
  loading: boolean;
  actionError: string | null;
}

export default function WineDetailPanel({
  wine,
  onClose,
  onVerify,
  onDelete,
  loading,
  actionError,
}: WineDetailPanelProps) {
  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
    };
    document.addEventListener('keydown', handler);
    return () => document.removeEventListener('keydown', handler);
  }, [onClose]);

  return (
    <>
      {/* Backdrop */}
      <div
        className="fixed inset-0 bg-black/40 z-40 backdrop-blur-sm"
        onClick={onClose}
        aria-hidden="true"
      />

      {/* Slide-over panel */}
      <div
        role="dialog"
        aria-modal="true"
        aria-label={wine.name}
        className="fixed inset-y-0 right-0 w-full max-w-md bg-white shadow-2xl z-50 flex flex-col"
      >
        {/* Header */}
        <div className="flex items-start gap-3 px-6 py-5 border-b border-stone-200">
          <div className="flex-1 min-w-0">
            <h2 className="text-xl font-bold text-stone-800 leading-tight">{wine.name}</h2>
            {wine.vintage && <p className="text-stone-500 text-sm mt-0.5">{wine.vintage}</p>}
          </div>
          <button
            onClick={onClose}
            aria-label="Close"
            className="flex-shrink-0 text-stone-400 hover:text-stone-600 transition-colors mt-0.5 p-1 -mr-1 rounded-lg hover:bg-stone-100"
          >
            <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth={2}
                d="M6 18L18 6M6 6l12 12"
              />
            </svg>
          </button>
        </div>

        {/* Scrollable content */}
        <div className="flex-1 overflow-y-auto">
          {/* Image */}
          <div className="aspect-video bg-gradient-to-b from-purple-800 to-purple-950 relative">
            {wine.image_url ? (
              <img
                src={absoluteImageUrl(wine.image_url)}
                alt={wine.name}
                className="w-full h-full object-cover"
              />
            ) : (
              <div className="w-full h-full flex items-center justify-center">
                <span className="text-7xl opacity-20">🍷</span>
              </div>
            )}
          </div>

          <div className="px-6 py-5 space-y-5">
            {/* Verified badge */}
            {wine.verified && (
              <div className="flex items-center gap-2 text-sm text-green-700 bg-green-50 px-3 py-2 rounded-lg w-fit">
                <svg className="w-4 h-4 flex-shrink-0" fill="currentColor" viewBox="0 0 20 20">
                  <path
                    fillRule="evenodd"
                    d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z"
                    clipRule="evenodd"
                  />
                </svg>
                Curator verified
              </div>
            )}

            {/* Metadata */}
            <dl className="space-y-2 text-sm">
              {wine.producer && (
                <div className="flex gap-3">
                  <dt className="text-stone-400 w-20 flex-shrink-0">Producer</dt>
                  <dd className="text-stone-700">{wine.producer}</dd>
                </div>
              )}
              {wine.variety && (
                <div className="flex gap-3">
                  <dt className="text-stone-400 w-20 flex-shrink-0">Grape</dt>
                  <dd className="text-stone-700">{wine.variety}</dd>
                </div>
              )}
              {wine.appellation && (
                <div className="flex gap-3">
                  <dt className="text-stone-400 w-20 flex-shrink-0">Region</dt>
                  <dd className="text-stone-700">{wine.appellation}</dd>
                </div>
              )}
            </dl>

            {/* Tasting note */}
            {wine.tasting_note && (
              <div>
                <h3 className="text-xs font-semibold text-stone-400 uppercase tracking-wider mb-2">
                  Tasting Note
                </h3>
                <p className="text-sm text-stone-600 leading-relaxed">{wine.tasting_note}</p>
              </div>
            )}

            {/* Pairings */}
            {wine.pairings.length > 0 && (
              <div>
                <h3 className="text-xs font-semibold text-stone-400 uppercase tracking-wider mb-2">
                  Food Pairings
                </h3>
                <div className="flex flex-wrap gap-2">
                  {wine.pairings.map((pairing) => (
                    <span
                      key={pairing}
                      className="text-xs bg-stone-100 text-stone-600 px-2.5 py-1 rounded-full"
                    >
                      {pairing}
                    </span>
                  ))}
                </div>
              </div>
            )}

            {/* Wine ID (debug) */}
            <p className="text-xs text-stone-300 font-mono break-all">{wine.wine_id}</p>
          </div>
        </div>

        {/* Actions */}
        <div className="px-6 py-4 border-t border-stone-200 space-y-3">
          {actionError && (
            <p className="text-xs text-red-600 bg-red-50 px-3 py-2 rounded-lg">{actionError}</p>
          )}
          <div className="flex gap-3">
            <button
              onClick={() => onVerify(!wine.verified)}
              disabled={loading}
              className={`flex-1 py-2.5 px-4 rounded-lg text-sm font-semibold transition-colors disabled:opacity-50 ${
                wine.verified
                  ? 'bg-stone-100 text-stone-600 hover:bg-stone-200'
                  : 'bg-purple-600 text-white hover:bg-purple-700'
              }`}
            >
              {loading ? 'Saving…' : wine.verified ? 'Unverify' : 'Mark verified'}
            </button>
            <button
              onClick={onDelete}
              disabled={loading}
              className="py-2.5 px-4 rounded-lg text-sm font-semibold text-red-600 bg-red-50 hover:bg-red-100 transition-colors disabled:opacity-50"
            >
              Delete
            </button>
          </div>
        </div>
      </div>
    </>
  );
}
