import { useEffect, useRef, useState } from 'react';
import type { WineRecord } from '../types/wine';
import { absoluteImageUrl, uploadWineImage, patchWine } from '../api/client';
import ImageCandidatePicker from './ImageCandidatePicker';

interface WineDetailPanelProps {
  wine: WineRecord;
  onClose: () => void;
  onVerify: (verified: boolean) => void;
  onDelete: () => void;
  onUpdate: (updated: WineRecord) => void;
  onImageUpdate: (wineId: string, newImageUrl: string) => void;
  loading: boolean;
  actionError: string | null;
}

interface EditDraft {
  name: string;
  producer: string;
  vintage: string;
  variety: string;
  appellation: string;
}

export default function WineDetailPanel({
  wine,
  onClose,
  onVerify,
  onDelete,
  onUpdate,
  onImageUpdate,
  loading,
  actionError,
}: WineDetailPanelProps) {
  const fileInputRef = useRef<HTMLInputElement>(null);
  const [editing, setEditing] = useState(false);
  const [draft, setDraft] = useState<EditDraft>({
    name: '',
    producer: '',
    vintage: '',
    variety: '',
    appellation: '',
  });
  const [saveLoading, setSaveLoading] = useState(false);
  const [saveError, setSaveError] = useState<string | null>(null);
  const [uploadLoading, setUploadLoading] = useState(false);
  const [uploadError, setUploadError] = useState<string | null>(null);
  const [localImageSrc, setLocalImageSrc] = useState<string | null>(null);
  const [pickerOpen, setPickerOpen] = useState(false);
  const [imageFlash, setImageFlash] = useState(false);

  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
    };
    document.addEventListener('keydown', handler);
    return () => document.removeEventListener('keydown', handler);
  }, [onClose]);

  useEffect(() => {
    setEditing(false);
    setSaveError(null);
    setLocalImageSrc(null);
    setUploadError(null);
    setPickerOpen(false);
    setImageFlash(false);
  }, [wine.wine_id]);

  const startEdit = () => {
    setDraft({
      name: wine.name,
      producer: wine.producer ?? '',
      vintage: wine.vintage ?? '',
      variety: wine.variety ?? '',
      appellation: wine.appellation ?? '',
    });
    setSaveError(null);
    setEditing(true);
  };

  const cancelEdit = () => {
    setEditing(false);
    setSaveError(null);
  };

  const saveEdit = async () => {
    const trimName = draft.name.trim();
    if (!trimName) {
      setSaveError('Wine name is required');
      return;
    }
    setSaveLoading(true);
    setSaveError(null);
    try {
      const updated = await patchWine(wine.wine_id, {
        name: trimName,
        producer: draft.producer.trim() || null,
        vintage: draft.vintage.trim() || null,
        variety: draft.variety.trim() || null,
        appellation: draft.appellation.trim() || null,
      });
      setEditing(false);
      onUpdate(updated);
    } catch (err) {
      setSaveError(err instanceof Error ? err.message : 'Save failed');
    } finally {
      setSaveLoading(false);
    }
  };

  const handlePickerSelect = (imageUrl: string) => {
    const bustedUrl = `${imageUrl}?t=${Date.now()}`;
    setLocalImageSrc(absoluteImageUrl(bustedUrl));
    onImageUpdate(wine.wine_id, bustedUrl);
    setPickerOpen(false);
    setImageFlash(true);
    setTimeout(() => setImageFlash(false), 700);
  };

  const openFilePicker = () => {
    setPickerOpen(false);
    fileInputRef.current?.click();
  };

  const handleFileChange = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;

    if (file.size > 10 * 1024 * 1024) {
      setUploadError('Image must be under 10 MB');
      if (fileInputRef.current) fileInputRef.current.value = '';
      return;
    }

    setUploadLoading(true);
    setUploadError(null);
    try {
      const result = await uploadWineImage(wine.wine_id, file);
      const bustedUrl = `${result.image_url}?t=${Date.now()}`;
      setLocalImageSrc(absoluteImageUrl(bustedUrl));
      onImageUpdate(wine.wine_id, bustedUrl);
    } catch (err) {
      setUploadError(err instanceof Error ? err.message : 'Upload failed');
    } finally {
      setUploadLoading(false);
      if (fileInputRef.current) fileInputRef.current.value = '';
    }
  };

  const imageSrc = localImageSrc ?? (wine.image_url ? absoluteImageUrl(wine.image_url) : null);

  const editFields: [string, keyof EditDraft, boolean][] = [
    ['Name', 'name', true],
    ['Producer', 'producer', false],
    ['Vintage', 'vintage', false],
    ['Grape', 'variety', false],
    ['Region', 'appellation', false],
  ];

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

        {/* File input always in DOM so onSwitchToUpload works when picker is open */}
        <input
          ref={fileInputRef}
          type="file"
          accept="image/jpeg,image/jpg"
          className="hidden"
          onChange={handleFileChange}
        />

        {pickerOpen ? (
          <div className="flex-1 flex flex-col min-h-0">
            <ImageCandidatePicker
              wineId={wine.wine_id}
              onSelect={handlePickerSelect}
              onCancel={() => setPickerOpen(false)}
              onSwitchToUpload={openFilePicker}
            />
          </div>
        ) : (
          /* Scrollable content */
          <div className="flex-1 overflow-y-auto">
            {/* Image section */}
            <div
              className={`h-[55vh] bg-gradient-to-b from-purple-800 to-purple-950 relative transition-all duration-700 ${imageFlash ? 'ring-2 ring-green-400/60' : ''}`}
            >
              {imageSrc ? (
                <>
                  <img
                    src={imageSrc}
                    alt={wine.name}
                    loading="lazy"
                    decoding="async"
                    className="w-full h-full object-contain"
                  />
                  {!uploadLoading && (
                    <>
                      <button
                        onClick={() => setPickerOpen(true)}
                        className="absolute bottom-2 left-2 bg-black/60 text-white text-xs px-2.5 py-1 rounded-md hover:bg-black/80 transition-colors"
                      >
                        Find image
                      </button>
                      <button
                        onClick={() => fileInputRef.current?.click()}
                        className="absolute bottom-2 right-2 bg-black/60 text-white text-xs px-2.5 py-1 rounded-md hover:bg-black/80 transition-colors"
                      >
                        Upload
                      </button>
                    </>
                  )}
                </>
              ) : (
                <div className="w-full h-full flex flex-col items-center justify-center gap-3">
                  <span className="text-7xl opacity-20">🍷</span>
                  {!uploadLoading && (
                    <div className="flex gap-2">
                      <button
                        onClick={() => fileInputRef.current?.click()}
                        className="text-xs text-white/60 hover:text-white/90 border border-white/30 hover:border-white/60 px-3 py-1.5 rounded-md transition-colors"
                      >
                        Upload photo
                      </button>
                      <button
                        onClick={() => setPickerOpen(true)}
                        className="text-xs text-white/60 hover:text-white/90 border border-white/30 hover:border-white/60 px-3 py-1.5 rounded-md transition-colors"
                      >
                        Find image
                      </button>
                    </div>
                  )}
                </div>
              )}

              {uploadLoading && (
                <div className="absolute inset-0 bg-black/50 flex items-center justify-center">
                  <div className="w-8 h-8 border-2 border-white border-t-transparent rounded-full animate-spin" />
                </div>
              )}
            </div>

            {uploadError && (
              <p className="mx-6 mt-3 text-xs text-red-600 bg-red-50 px-3 py-2 rounded-lg">
                {uploadError}
              </p>
            )}

            <div className="px-6 py-5 space-y-5">
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

              {/* Details section */}
              <div>
                <div className="flex items-center justify-between mb-3">
                  <h3 className="text-xs font-semibold text-stone-400 uppercase tracking-wider">
                    Details
                  </h3>
                  {!editing ? (
                    <button
                      onClick={startEdit}
                      className="text-xs text-purple-600 hover:text-purple-700 font-medium flex items-center gap-1"
                    >
                      <svg
                        className="w-3.5 h-3.5"
                        fill="none"
                        stroke="currentColor"
                        viewBox="0 0 24 24"
                      >
                        <path
                          strokeLinecap="round"
                          strokeLinejoin="round"
                          strokeWidth={2}
                          d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z"
                        />
                      </svg>
                      Edit
                    </button>
                  ) : (
                    <div className="flex items-center gap-3">
                      <button
                        onClick={cancelEdit}
                        className="text-xs text-stone-400 hover:text-stone-600 font-medium"
                      >
                        Cancel
                      </button>
                      <button
                        onClick={saveEdit}
                        disabled={saveLoading}
                        className="text-xs text-white bg-purple-600 hover:bg-purple-700 font-semibold px-3 py-1 rounded-md disabled:opacity-50 transition-colors"
                      >
                        {saveLoading ? 'Saving…' : 'Save'}
                      </button>
                    </div>
                  )}
                </div>

                {editing ? (
                  <div className="space-y-2.5">
                    {editFields.map(([label, field, required]) => (
                      <div key={field} className="flex gap-3 items-center">
                        <label className="text-stone-400 text-xs w-20 flex-shrink-0">
                          {label}
                          {required && <span className="text-red-400 ml-0.5">*</span>}
                        </label>
                        <input
                          type="text"
                          value={draft[field]}
                          onChange={(e) => setDraft((d) => ({ ...d, [field]: e.target.value }))}
                          className="flex-1 text-sm border border-stone-300 rounded-md px-2.5 py-1.5 focus:outline-none focus:ring-2 focus:ring-purple-500 focus:border-transparent"
                          placeholder={required ? 'Required' : 'Optional'}
                        />
                      </div>
                    ))}
                    {saveError && <p className="text-xs text-red-600 mt-1">{saveError}</p>}
                  </div>
                ) : (
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
                    {!wine.producer && !wine.variety && !wine.appellation && (
                      <p className="text-xs text-stone-300 italic">No details extracted</p>
                    )}
                  </dl>
                )}
              </div>

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

              <p className="text-xs text-stone-300 font-mono break-all">{wine.wine_id}</p>
            </div>
          </div>
        )}

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
