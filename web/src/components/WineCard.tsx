import { useState, useEffect } from 'react';
import { createPortal } from 'react-dom';
import type { WineRecord } from '../types/wine';
import { absoluteImageUrl } from '../api/client';

type Density = 4 | 8 | 12 | 16;

interface WineCardProps {
  wine: WineRecord;
  density: Density;
  onClick: () => void;
}

export default function WineCard({ wine, density, onClick }: WineCardProps) {
  const [zoomOpen, setZoomOpen] = useState(false);

  useEffect(() => {
    if (!zoomOpen) return;
    const handler = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        e.stopPropagation();
        setZoomOpen(false);
      }
    };
    document.addEventListener('keydown', handler);
    return () => document.removeEventListener('keydown', handler);
  }, [zoomOpen]);

  const imageSrc = wine.image_url ? absoluteImageUrl(wine.image_url) : null;

  const showName = density <= 8;

  // Zoom button: smaller at higher densities, always visible at 16
  const zoomBtnSize =
    density <= 4 ? 'w-7 h-7 text-sm' : density <= 8 ? 'w-6 h-6 text-xs' : 'w-5 h-5 text-[10px]';
  const zoomBtnVisibility =
    density >= 16
      ? 'opacity-50'
      : 'opacity-0 group-hover:opacity-100 [@media(hover:none)]:opacity-100';

  return (
    <>
      <div
        role="button"
        tabIndex={0}
        onClick={onClick}
        onKeyDown={(e) => {
          if (e.key === 'Enter' || e.key === ' ') {
            e.preventDefault();
            onClick();
          }
        }}
        aria-label={wine.name}
        title={wine.name}
        className="group w-full text-left focus:outline-none focus-visible:ring-2 focus-visible:ring-purple-500 rounded-xl cursor-pointer"
      >
        <div className="aspect-[1/4] rounded-xl overflow-hidden bg-gradient-to-b from-purple-800 to-purple-950 relative shadow-md group-hover:shadow-lg transition-shadow">
          {imageSrc ? (
            <img
              src={imageSrc}
              alt={wine.name}
              loading="lazy"
              decoding="async"
              className="w-full h-full object-contain p-2"
            />
          ) : (
            <div className="w-full h-full flex items-center justify-center">
              <span className="text-5xl opacity-20">🍷</span>
            </div>
          )}

          {wine.verified && (
            <div className="absolute top-2 left-2 bg-green-500 text-white text-xs w-5 h-5 rounded-full flex items-center justify-center font-bold shadow">
              ✓
            </div>
          )}

          {imageSrc && (
            <button
              onClick={(e) => {
                e.stopPropagation();
                setZoomOpen(true);
              }}
              aria-label="Inspect label"
              className={`absolute top-2 right-2 ${zoomBtnSize} rounded-full bg-black/50 text-white ${zoomBtnVisibility} flex items-center justify-center transition-opacity leading-none`}
            >
              ⊕
            </button>
          )}
        </div>

        {showName && (
          <div className={density <= 4 ? 'mt-2 px-1' : 'mt-1 px-0.5'}>
            <p
              className={
                density <= 4
                  ? 'text-stone-800 text-sm font-semibold leading-tight line-clamp-2'
                  : 'text-stone-700 text-[9px] font-semibold leading-tight line-clamp-1'
              }
            >
              {wine.name}
            </p>
            {wine.vintage && (
              <p
                className={
                  density <= 4
                    ? 'text-stone-500 text-xs mt-0.5'
                    : 'text-stone-400 text-[8px] mt-0.5'
                }
              >
                {wine.vintage}
              </p>
            )}
          </div>
        )}
      </div>

      {zoomOpen &&
        imageSrc &&
        createPortal(
          <div
            className="fixed inset-0 z-50 bg-black/80 flex items-center justify-center p-4"
            onClick={() => setZoomOpen(false)}
            role="dialog"
            aria-modal="true"
            aria-label={`Inspect label: ${wine.name}`}
          >
            <div
              className="max-w-xs w-full flex flex-col bg-stone-900 rounded-2xl overflow-hidden shadow-2xl"
              onClick={(e) => e.stopPropagation()}
            >
              <div className="flex items-center justify-between px-4 py-3 border-b border-stone-700">
                <span className="text-sm font-semibold text-stone-100 truncate pr-3">
                  {wine.name}
                  {wine.vintage ? ` · ${wine.vintage}` : ''}
                </span>
                <button
                  onClick={() => setZoomOpen(false)}
                  aria-label="Close"
                  className="w-7 h-7 flex-shrink-0 rounded-full bg-stone-700 text-stone-300 hover:bg-stone-600 flex items-center justify-center text-sm transition-colors"
                >
                  ✕
                </button>
              </div>
              <div className="flex items-center justify-center bg-stone-950 p-4">
                <img
                  src={imageSrc}
                  alt={wine.name}
                  className="max-w-full max-h-[75vh] object-contain"
                />
              </div>
              <div className="px-4 py-2 border-t border-stone-700">
                <p className="text-xs text-stone-500">Press Esc to close</p>
              </div>
            </div>
          </div>,
          document.body,
        )}
    </>
  );
}
