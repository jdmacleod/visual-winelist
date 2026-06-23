import { useEffect, useState } from 'react';
import type { ImageCandidate } from '../types/wine';
import { fetchImageCandidates, setImageFromUrl } from '../api/client';

interface ImageCandidatePickerProps {
  wineId: string;
  onSelect: (imageUrl: string) => void;
  onCancel: () => void;
  onSwitchToUpload: () => void;
}

type Phase = 'searching' | 'loaded' | 'error';

function domainOf(url: string): string {
  try {
    return new URL(url).hostname;
  } catch {
    return '';
  }
}

function vintageOf(title: string): string | null {
  const m = title.match(/((?:19|20)\d{2})/);
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
  const [retryKey, setRetryKey] = useState(0);
  const [uploadingIndex, setUploadingIndex] = useState<number | null>(null);
  const [uploadError, setUploadError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    setPhase('searching');
    setCandidates([]);
    setUploadError(null);
    fetchImageCandidates(wineId)
      .then((c) => {
        if (!cancelled) {
          setCandidates(c);
          setPhase('loaded');
        }
      })
      .catch(() => {
        if (!cancelled) setPhase('error');
      });
    return () => {
      cancelled = true;
    };
  }, [wineId, retryKey]);

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

  const header = (
    <div className="flex items-center justify-between px-3 py-2 flex-shrink-0">
      <span className="text-xs font-semibold text-stone-400 uppercase tracking-wider">
        Candidates from web
      </span>
      <button onClick={onCancel} className="text-xs text-stone-400 hover:text-white underline">
        Cancel
      </button>
    </div>
  );

  if (phase === 'searching') {
    return (
      <div className="absolute inset-0 bg-black/50 flex flex-col items-center justify-center gap-2">
        <div className="w-6 h-6 border-2 border-purple-400 border-t-transparent rounded-full animate-spin" />
        <span className="text-sm text-white">Searching Brave...</span>
      </div>
    );
  }

  if (phase === 'error') {
    return (
      <div className="absolute inset-0 bg-stone-900 flex flex-col">
        {header}
        <div className="flex-1 flex flex-col items-center justify-center gap-2">
          <span className="text-sm text-red-400">Couldn't load candidates</span>
          <button
            onClick={() => setRetryKey((k) => k + 1)}
            className="text-xs text-stone-300 hover:text-white underline"
          >
            Try again
          </button>
        </div>
      </div>
    );
  }

  if (candidates.length === 0) {
    return (
      <div className="absolute inset-0 bg-stone-900 flex flex-col">
        {header}
        <div className="flex-1 flex flex-col items-center justify-center gap-2">
          <span className="text-sm text-stone-400">No candidates found</span>
          <button
            onClick={onSwitchToUpload}
            className="text-xs text-stone-400 hover:text-stone-200"
          >
            Upload a photo instead →
          </button>
        </div>
      </div>
    );
  }

  return (
    <div className="absolute inset-0 bg-stone-900 flex flex-col">
      {header}
      {uploadError && <p className="text-xs text-red-400 px-3 pb-1 flex-shrink-0">{uploadError}</p>}
      <div className="flex-1 flex items-center px-3 gap-1.5 min-h-0">
        {candidates.map((c, idx) => {
          const isUploading = uploadingIndex === idx;
          const isDimmed = uploadingIndex !== null && !isUploading;
          const vintage = vintageOf(c.title);
          const domain = domainOf(c.source_url);

          return (
            <button
              key={idx}
              onClick={() => void handleSelect(c, idx)}
              disabled={uploadingIndex !== null}
              aria-label={`Use image from ${domain}: ${c.title}`}
              className={`flex-1 min-w-0 flex flex-col focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-purple-500 rounded-sm transition-opacity ${isDimmed ? 'opacity-40' : ''}`}
            >
              <div className="relative aspect-[3/5] bg-stone-700 rounded-sm overflow-hidden">
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
                {c.title && <p className="text-xs text-stone-500 truncate">{c.title}</p>}
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
  );
}
