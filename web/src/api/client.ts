import type {
  ImageCandidate,
  ScanSummary,
  SearchResponse,
  StatusFilter,
  SortOption,
  WineRecord,
  WineStats,
} from '../types/wine';

// In dev: Vite proxies /wines and /curate to http://localhost:8000.
// In production: nginx handles routing. Override with VITE_API_BASE_URL if needed.
const BASE_URL = import.meta.env['VITE_API_BASE_URL'] ?? '';

async function timedFetch(input: string, init?: RequestInit): Promise<Response> {
  const method = init?.method ?? 'GET';
  const t0 = performance.now();
  const res = await fetch(input, init);
  const ms = Math.round(performance.now() - t0);
  console.debug(`[api] ${method} ${input} → ${res.status} (${ms}ms)`);
  return res;
}

// Map the UI sort label to backend sort+order params.
const SORT_PARAMS: Record<SortOption, { sort: string; order: string }> = {
  newest: { sort: 'created_at', order: 'desc' },
  oldest: { sort: 'created_at', order: 'asc' },
  name_asc: { sort: 'name', order: 'asc' },
  producer_asc: { sort: 'producer', order: 'asc' },
  verified: { sort: 'verified', order: 'desc' },
};

export async function searchWines(
  q: string,
  page: number,
  pageSize: number = 20,
  status: StatusFilter = 'all',
  sortOption: SortOption = 'newest',
): Promise<SearchResponse> {
  const { sort, order } = SORT_PARAMS[sortOption];
  const params = new URLSearchParams({
    q,
    page: String(page),
    page_size: String(pageSize),
    status,
    sort,
    order,
  });
  const res = await timedFetch(`${BASE_URL}/wines/search?${params}`);
  if (!res.ok) throw new Error(`Search failed: ${res.status}`);
  return res.json() as Promise<SearchResponse>;
}

export async function curate(
  wineId: string,
  verified: boolean,
): Promise<{ wine_id: string; verified: boolean }> {
  const res = await timedFetch(`${BASE_URL}/curate`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ wine_id: wineId, verified }),
  });
  if (!res.ok) throw new Error(`Curate failed: ${res.status}`);
  return res.json() as Promise<{ wine_id: string; verified: boolean }>;
}

export async function deleteWine(wineId: string): Promise<void> {
  const res = await timedFetch(`${BASE_URL}/wines/${wineId}`, { method: 'DELETE' });
  if (!res.ok && res.status !== 404) throw new Error(`Delete failed: ${res.status}`);
}

export async function uploadWineImage(
  wineId: string,
  file: File,
): Promise<{ wine_id: string; image_url: string }> {
  const formData = new FormData();
  formData.append('file', file);
  const res = await timedFetch(`${BASE_URL}/wines/${wineId}/image`, {
    method: 'POST',
    body: formData,
  });
  if (!res.ok) throw new Error(`Upload failed: ${res.status}`);
  return res.json() as Promise<{ wine_id: string; image_url: string }>;
}

export async function patchWine(
  wineId: string,
  fields: Partial<Pick<WineRecord, 'name' | 'producer' | 'vintage' | 'variety' | 'appellation'>>,
): Promise<WineRecord> {
  const res = await timedFetch(`${BASE_URL}/wines/${wineId}`, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(fields),
  });
  if (!res.ok) throw new Error(`Update failed: ${res.status}`);
  return res.json() as Promise<WineRecord>;
}

export async function fetchImageCandidates(
  wineId: string,
  q?: string,
): Promise<{ candidates: ImageCandidate[]; query: string }> {
  const url = q
    ? `${BASE_URL}/wines/${wineId}/image-candidates?q=${encodeURIComponent(q)}`
    : `${BASE_URL}/wines/${wineId}/image-candidates`;
  const res = await timedFetch(url);
  if (!res.ok) throw new Error(`Candidates failed: ${res.status}`);
  const body = (await res.json()) as { candidates: ImageCandidate[]; query: string };
  return { candidates: body.candidates, query: body.query };
}

export async function fetchWineStats(): Promise<WineStats> {
  const res = await timedFetch(`${BASE_URL}/wines/stats`);
  if (!res.ok) throw new Error(`Stats failed: ${res.status}`);
  return res.json() as Promise<WineStats>;
}

export async function fetchRecentScans(
  limit = 10,
): Promise<{ scans: ScanSummary[]; hit_rate: number | null }> {
  const res = await timedFetch(`${BASE_URL}/scans/recent?limit=${limit}`);
  if (!res.ok) throw new Error(`Recent scans failed: ${res.status}`);
  return res.json() as Promise<{ scans: ScanSummary[]; hit_rate: number | null }>;
}

export async function setImageFromUrl(
  wineId: string,
  url: string,
): Promise<{ wine_id: string; image_url: string }> {
  const res = await timedFetch(`${BASE_URL}/wines/${wineId}/image-from-url`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ url }),
  });
  if (!res.ok) {
    let detail = '';
    try {
      detail = ((await res.json()) as { detail?: string }).detail ?? '';
    } catch {
      // ignore parse error
    }
    if (res.status === 404 && detail === 'image_expired') throw new Error('image_expired');
    throw new Error(`Upload failed: ${res.status}`);
  }
  return res.json() as Promise<{ wine_id: string; image_url: string }>;
}

export function absoluteImageUrl(relativeUrl: string): string {
  return `${BASE_URL}${relativeUrl}`;
}
