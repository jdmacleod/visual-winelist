import { useState, useEffect, useCallback, useRef } from 'react';
import { searchWines, curate, deleteWine, fetchWineStats, fetchRecentScans } from './api/client';
import type { WineRecord, SearchResponse, StatusFilter, SortOption, WineStats } from './types/wine';
import WineCard from './components/WineCard';
import WineDetailPanel from './components/WineDetailPanel';
import ConfirmModal from './components/ConfirmModal';
import Pagination from './components/Pagination';

const ROWS_PER_PAGE = 5;

type Density = 4 | 8 | 12 | 16;
const DENSITIES: Density[] = [4, 8, 12, 16];
const DENSITY_GRID: Record<Density, string> = {
  4: 'grid-cols-4 gap-4',
  8: 'grid-cols-8 gap-2',
  12: 'grid-cols-12 gap-1.5',
  16: 'grid-cols-16 gap-1',
};

const STATUS_LABELS: Record<StatusFilter, string> = {
  all: 'All',
  verified: 'Verified',
  unverified: 'Unverified',
  no_image: 'No Image',
};

const SORT_LABELS: Record<SortOption, string> = {
  newest: 'Newest',
  oldest: 'Oldest',
  name_asc: 'Name A→Z',
  producer_asc: 'Producer A→Z',
  verified: 'Verified First',
};

export default function App() {
  const [query, setQuery] = useState('');
  const [debouncedQuery, setDebouncedQuery] = useState('');
  const [page, setPage] = useState(1);
  const [status, setStatus] = useState<StatusFilter>('all');
  const [sortOption, setSortOption] = useState<SortOption>('newest');
  const [results, setResults] = useState<SearchResponse | null>(null);
  const [loading, setLoading] = useState(false);
  const [fetchError, setFetchError] = useState<string | null>(null);
  const [selected, setSelected] = useState<WineRecord | null>(null);
  const [actionLoading, setActionLoading] = useState(false);
  const [actionError, setActionError] = useState<string | null>(null);
  const [deleteTarget, setDeleteTarget] = useState<WineRecord | null>(null);
  const [wineStats, setWineStats] = useState<WineStats | null>(null);
  const [hitRate, setHitRate] = useState<number | null>(null);
  const fetchIdRef = useRef(0);
  const [density, setDensity] = useState<Density>(() => {
    const saved = localStorage.getItem('wine-gallery-density');
    return saved === '4' || saved === '8' || saved === '12' || saved === '16'
      ? (Number(saved) as Density)
      : 12;
  });

  const pageSize = density * ROWS_PER_PAGE;

  useEffect(() => {
    const timer = setTimeout(() => {
      setDebouncedQuery(query);
      setPage(1);
    }, 300);
    return () => clearTimeout(timer);
  }, [query]);

  useEffect(() => {
    localStorage.setItem('wine-gallery-density', String(density));
  }, [density]);

  // Reset to page 1 when filter, sort, or density changes.
  useEffect(() => {
    setPage(1);
  }, [status, sortOption, density]);

  // Clear stale action errors when the selected wine changes.
  useEffect(() => {
    setActionError(null);
  }, [selected?.wine_id]);

  const fetchStats = useCallback(async () => {
    try {
      const [stats, recent] = await Promise.all([fetchWineStats(), fetchRecentScans()]);
      setWineStats(stats);
      setHitRate(recent.hit_rate);
    } catch {
      // stats are non-critical; silently ignore
    }
  }, []);

  useEffect(() => {
    void fetchStats();
  }, [fetchStats]);

  const fetchWines = useCallback(async () => {
    const thisId = ++fetchIdRef.current;
    setLoading(true);
    setFetchError(null);
    try {
      const data = await searchWines(debouncedQuery, page, pageSize, status, sortOption);
      if (thisId !== fetchIdRef.current) return;
      setResults(data);
    } catch (err) {
      if (thisId !== fetchIdRef.current) return;
      setFetchError(
        err instanceof Error
          ? err.message
          : 'Could not reach backend — is it running on localhost:8000?',
      );
    } finally {
      if (thisId === fetchIdRef.current) setLoading(false);
    }
  }, [debouncedQuery, page, pageSize, status, sortOption]);

  useEffect(() => {
    void fetchWines();
  }, [fetchWines]);

  const handleVerify = useCallback(
    async (verified: boolean) => {
      if (!selected) return;
      setActionLoading(true);
      setActionError(null);
      try {
        const updated = await curate(selected.wine_id, verified);
        const patch = { verified: updated.verified };
        setResults((prev) => {
          if (!prev) return null;
          const old = prev.results.find((w) => w.wine_id === updated.wine_id);
          const verifiedDelta = old ? (updated.verified ? 1 : 0) - (old.verified ? 1 : 0) : 0;
          return {
            ...prev,
            results: prev.results.map((w) =>
              w.wine_id === updated.wine_id ? { ...w, ...patch } : w,
            ),
            verified_total: prev.verified_total + verifiedDelta,
          };
        });
        setSelected((prev) => (prev ? { ...prev, ...patch } : null));
      } catch (err) {
        setActionError(err instanceof Error ? err.message : 'Action failed');
      } finally {
        setActionLoading(false);
      }
    },
    [selected],
  );

  const handleUpdate = useCallback((updated: WineRecord) => {
    setResults((prev) => {
      if (!prev) return null;
      const old = prev.results.find((w) => w.wine_id === updated.wine_id);
      const verifiedDelta = old ? (updated.verified ? 1 : 0) - (old.verified ? 1 : 0) : 0;
      return {
        ...prev,
        results: prev.results.map((w) => (w.wine_id === updated.wine_id ? updated : w)),
        verified_total: prev.verified_total + verifiedDelta,
      };
    });
    setSelected(updated);
  }, []);

  const handleImageUpdate = useCallback(
    (wineId: string, newImageUrl: string) => {
      setResults((prev) =>
        prev
          ? {
              ...prev,
              results: prev.results.map((w) =>
                w.wine_id === wineId ? { ...w, image_url: newImageUrl } : w,
              ),
            }
          : null,
      );
      setSelected((prev) => (prev ? { ...prev, image_url: newImageUrl } : null));
      void fetchStats();
    },
    [fetchStats],
  );

  const handleDelete = useCallback(() => {
    if (!selected) return;
    setDeleteTarget(selected);
  }, [selected]);

  const handleConfirmDelete = useCallback(async () => {
    if (!deleteTarget) return;
    setActionLoading(true);
    setActionError(null);
    try {
      await deleteWine(deleteTarget.wine_id);
      setDeleteTarget(null);
      setSelected(null);
      await fetchWines();
    } catch (err) {
      setActionError(err instanceof Error ? err.message : 'Delete failed');
      setDeleteTarget(null);
    } finally {
      setActionLoading(false);
    }
  }, [deleteTarget, fetchWines]);

  const totalPages = results ? Math.ceil(results.total / pageSize) : 0;

  return (
    <div className="min-h-screen bg-stone-50">
      {/* Header */}
      <header className="bg-white border-b border-stone-200">
        <div className="max-w-7xl mx-auto px-6 py-4 flex items-center gap-3">
          <span className="text-2xl" aria-hidden="true">
            🍷
          </span>
          <div>
            <h1 className="text-xl font-semibold text-stone-800">Visual Winelist Curator</h1>
            {results && (
              <p className="text-xs text-stone-400 mt-0.5">
                {(wineStats?.total ?? results.total).toLocaleString()} wine
                {(wineStats?.total ?? results.total) !== 1 ? 's' : ''} in cache
                {results.verified_total > 0 && (
                  <span className="text-green-600">
                    {' '}
                    · {results.verified_total.toLocaleString()} verified
                  </span>
                )}
                {wineStats && wineStats.total > 0 && (
                  <span className="text-stone-400">
                    {' '}
                    · {wineStats.with_image.toLocaleString()} with images (
                    {Math.round((wineStats.with_image / wineStats.total) * 100)}%)
                  </span>
                )}
                {hitRate !== null && (
                  <span className="text-stone-400"> · {hitRate}% cache hit rate</span>
                )}
              </p>
            )}
          </div>
        </div>
      </header>

      {/* Search + filter/sort bar */}
      <div className="bg-white border-b border-stone-200">
        <div className="max-w-7xl mx-auto px-6 py-3 space-y-2.5">
          <input
            type="search"
            placeholder="Search wines, producers, appellations…"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            className="w-full max-w-lg px-4 py-2 border border-stone-300 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-purple-500 focus:border-transparent"
          />

          {/* Filter pills + sort */}
          <div className="flex items-center justify-between gap-3 flex-wrap">
            <div className="flex items-center gap-1.5" role="group" aria-label="Filter wines">
              {(Object.keys(STATUS_LABELS) as StatusFilter[]).map((s) => (
                <button
                  key={s}
                  onClick={() => setStatus(s)}
                  className={`px-3 py-1 rounded-full text-xs font-medium transition-colors ${
                    status === s
                      ? 'bg-purple-600 text-white'
                      : 'bg-stone-100 text-stone-600 hover:bg-stone-200'
                  }`}
                >
                  {STATUS_LABELS[s]}
                </button>
              ))}
            </div>

            <div className="flex items-center gap-3">
              <div className="flex items-center gap-2">
                <label htmlFor="sort-select" className="text-xs text-stone-400 whitespace-nowrap">
                  Sort:
                </label>
                <select
                  id="sort-select"
                  value={sortOption}
                  onChange={(e) => setSortOption(e.target.value as SortOption)}
                  className="text-xs border border-stone-200 rounded-md px-2 py-1 text-stone-600 bg-white focus:outline-none focus:ring-2 focus:ring-purple-500"
                >
                  {(Object.keys(SORT_LABELS) as SortOption[]).map((s) => (
                    <option key={s} value={s}>
                      {SORT_LABELS[s]}
                    </option>
                  ))}
                </select>
              </div>

              <div
                className="flex border border-stone-200 rounded-lg overflow-hidden"
                role="group"
                aria-label="Gallery density"
              >
                {DENSITIES.map((d) => (
                  <button
                    key={d}
                    onClick={() => setDensity(d)}
                    aria-pressed={density === d}
                    className={`px-2.5 py-1 text-xs font-semibold border-r border-stone-200 last:border-r-0 transition-colors ${
                      density === d
                        ? 'bg-purple-600 text-white'
                        : 'bg-white text-stone-500 hover:bg-stone-100'
                    }`}
                  >
                    {d}
                  </button>
                ))}
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* Main */}
      <main className="max-w-7xl mx-auto px-6 py-6">
        {loading && (
          <div className="flex justify-center py-16">
            <div className="w-6 h-6 border-2 border-purple-600 border-t-transparent rounded-full animate-spin" />
          </div>
        )}

        {fetchError && (
          <div className="bg-red-50 border border-red-200 rounded-xl p-4 text-sm text-red-700">
            <strong>Error:</strong> {fetchError}
          </div>
        )}

        {!loading && results && results.results.length === 0 && (
          <div className="text-center py-24 text-stone-400">
            <p className="text-5xl mb-4" aria-hidden="true">
              🍷
            </p>
            <p className="text-lg font-medium text-stone-500">
              {status === 'all' && !query ? 'No wines cached yet' : 'No wines match this filter'}
            </p>
            <p className="text-sm mt-2">
              {status === 'all' && !query
                ? 'Scan some wine lists with the iOS app first'
                : 'Try a different filter or search term'}
            </p>
          </div>
        )}

        {!loading && results && results.results.length > 0 && (
          <>
            <div className={`grid ${DENSITY_GRID[density]}`}>
              {results.results.map((wine) => (
                <WineCard
                  key={wine.wine_id}
                  wine={wine}
                  density={density}
                  onClick={() => setSelected(wine)}
                />
              ))}
            </div>

            {totalPages > 1 && (
              <Pagination page={page} totalPages={totalPages} onPageChange={setPage} />
            )}
          </>
        )}
      </main>

      {selected && (
        <WineDetailPanel
          wine={selected}
          onClose={() => setSelected(null)}
          onVerify={handleVerify}
          onDelete={handleDelete}
          onUpdate={handleUpdate}
          onImageUpdate={handleImageUpdate}
          loading={actionLoading}
          actionError={actionError}
        />
      )}

      {deleteTarget && (
        <ConfirmModal
          title="Delete wine?"
          message={`"${deleteTarget.name}" will be permanently removed from the cache.`}
          confirmLabel="Delete"
          loading={actionLoading}
          onConfirm={handleConfirmDelete}
          onCancel={() => setDeleteTarget(null)}
        />
      )}
    </div>
  );
}
