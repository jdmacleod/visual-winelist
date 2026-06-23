import { useEffect, useRef, useState } from 'react';
import type { ImageCandidate } from '../types/wine';
import { fetchImageCandidates, setImageFromUrl } from '../api/client';

interface ImageCandidatePickerProps {
  wineId: string;
  onSelect: (imageUrl: string) => void;
  onCancel: () => void;
  onSwitchToUpload: () => void;
}

type Phase = 'searching' | 'loaded' | 'error';

interface SearchReq {
  q: string | undefined;
  tick: number;
}

function domainOf(url: string): string {
  try {
    return new URL(url).hostname;
  } catch {
    return '';
  }
}

function vintageOf(title: string): string | null {
  const m = title.match(/\b((?:19|20)\d{2})\b/);
  return m ? m[1] : null;
}

export default function ImageCandidatePicker({
  wineId,
  onSelect,
  onCancel,
  onSwitchToUpload,
}: ImageCandidatePickerProps) {
  const [phase, setPhase] = useState<Phase>('searching');
  const [candidates, setCandidates] = useState<ImageCandidate[]>([]);
  const [inputQuery, setInputQuery] = useState('');
  const [searchReq, setSearchReq] = useState<SearchReq>({ q: undefined, tick: 0 });
  const [uploadingIndex, setUploadingIndex] = useState<number | null>(null);
  const [uploadError, setUploadError] = useState<string | null>(null);
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    let cancelled = false;
    setPhase('searching');
    setCandidates([]);
    setUploadError(null);
    fetchImageCandidates(wineId, searchReq.q)
      .then(({ candidates: c, query }) => {
        if (!cancelled) {
          setCandidates(c);
          setInputQuery(query);
          setPhase('loaded');
        }
      })
      .catch(() => {
        if (!cancelled) setPhase('error');
      });
    return () => {
      cancelled = true;
    };
  }, [wineId, searchReq]);

  const handleSearch = () => {
    const trimmed = inputQuery.trim();
    if (!trimmed) return;
    setSearchReq((r) => ({ q: trimmed, tick: r.tick + 1 }));
  };

  const handleKeyDown = (e: React.KeyboardEvent<HTMLInputElement>) => {
    if (e.key === 'Enter') handleSearch();
  };

  const handleSelect = async (candidate: ImageCandidate, idx: number) => {
    if (uploadingIndex !== null) return;
    setUploadingIndex(idx);
    setUploadError(null);
    try {
      const result = await setImageFromUrl(wineId, candidate.url);
      onSelect(result.image_url);
    } catch (err) {
      const msg = err instanceof Error ? err.message : '';
      setUploadError(
        msg === 'image_expired'
          ? 'This image is no longer available — try another'
          : 'Upload failed — try another',
      );
      setUploadingIndex(null);
    }
  };

  return (
    <div className="flex-1 flex flex-col bg-stone-900 min-h-0">
      {/* Header: query input + controls */}
      <div className="flex items-center gap-2 px-3 py-2 flex-shrink-0 border-b border-stone-700">
        <div className="flex-1 min-w-0">
          <input
            ref={inputRef}
            type="text"
            value={inputQuery}
            onChange={(e) => setInputQuery(e.target.value)}
            onKeyDown={handleKeyDown}
            disabled={phase === 'searching'}
            placeholder="Search query…"
            className="w-full text-xs bg-stone-800 text-stone-100 placeholder-stone-500 border border-stone-600 rounded px-2 py-1 focus:outline-none focus:ring-1 focus:ring-purple-500 disabled:opacity-40"
          />
        </div>
        <button
          onClick={handleSearch}
          disabled={phase === 'searching' || !inputQuery.trim()}
          className="text-xs text-white bg-purple-600 hover:bg-purple-700 disabled:opacity-40 px-2.5 py-1 rounded transition-colors"
        >
          Search
        </button>
        <button onClick={onCancel} className="text-xs text-stone-400 hover:text-white underline">
          Cancel
        </button>
      </div>

      {uploadError && (
        <p className="text-xs text-red-400 px-3 py-1 flex-shrink-0 bg-stone-800">{uploadError}</p>
      )}

      {/* Body */}
      {phase === 'searching' && (
        <div className="flex-1 flex flex-col items-center justify-center gap-2">
          <div className="w-6 h-6 border-2 border-purple-400 border-t-transparent rounded-full animate-spin" />
          <span className="text-sm text-stone-400">Searching Brave…</span>
        </div>
      )}

      {phase === 'error' && (
        <div className="flex-1 flex flex-col items-center justify-center gap-2">
          <span className="text-sm text-red-400">Couldn't load candidates</span>
          <button
            onClick={() => setSearchReq((r) => ({ ...r, tick: r.tick + 1 }))}
            className="text-xs text-stone-300 hover:text-white underline"
          >
            Try again
          </button>
        </div>
      )}

      {phase === 'loaded' && candidates.length === 0 && (
        <div className="flex-1 flex flex-col items-center justify-center gap-2">
          <span className="text-sm text-stone-400">No candidates found</span>
          <button
            onClick={onSwitchToUpload}
            className="text-xs text-stone-400 hover:text-stone-200"
          >
            Upload a photo instead →
          </button>
        </div>
      )}

      {phase === 'loaded' && candidates.length > 0 && (
        <div className="flex-1 overflow-y-auto p-2 min-h-0">
          <div className="grid grid-cols-3 gap-1.5">
            {candidates.map((c, idx) => {
              const isUploading = uploadingIndex === idx;
              const isDimmed = uploadingIndex !== null && !isUploading;
              const vintage = vintageOf(c.title);
              const domain = domainOf(c.source_url);

              return (
                <button
                  key={c.url}
                  onClick={() => void handleSelect(c, idx)}
                  disabled={uploadingIndex !== null}
                  aria-label={`Use image from ${domain}: ${c.title}`}
                  className={`flex flex-col focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-purple-500 rounded-sm transition-opacity ${isDimmed ? 'opacity-40' : ''}`}
                >
                  <div className="relative aspect-[3/5] bg-stone-700 rounded-sm overflow-hidden w-full">
                    <div className="absolute inset-0 bg-stone-200 animate-pulse" />
                    <img
                      src={c.thumbnail_url}
                      alt=""
                      className="absolute inset-0 w-full h-full object-cover opacity-0 transition-opacity duration-300"
                      onLoad={(e) => {
                        (e.target as HTMLImageElement).classList.remove('opacity-0');
                        (e.target as HTMLImageElement).classList.add('opacity-100');
                      }}
                    />
                    {isUploading && (
                      <div className="absolute inset-0 bg-black/50 flex items-center justify-center">
                        <div className="w-4 h-4 border-2 border-white border-t-transparent rounded-full animate-spin" />
                      </div>
                    )}
                  </div>
                  <div className="min-w-0 mt-0.5 text-left">
                    {c.title && (
                      <p className="text-xs text-stone-500 truncate leading-tight">{c.title}</p>
                    )}
                    <div className="flex items-center gap-1">
                      {domain && <p className="text-xs text-stone-400 truncate">{domain}</p>}
                      {vintage && <p className="text-xs text-purple-400 shrink-0">{vintage}</p>}
                    </div>
                  </div>
                </button>
              );
            })}
          </div>
        </div>
      )}
    </div>
  );
}
