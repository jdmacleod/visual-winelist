import type { SearchResponse, StatusFilter, SortOption } from '../types/wine';

// In dev: Vite proxies /wines and /curate to http://localhost:8000.
// In production: nginx handles routing. Override with VITE_API_BASE_URL if needed.
const BASE_URL = import.meta.env['VITE_API_BASE_URL'] ?? '';

// Map the UI sort label to backend sort+order params.
const SORT_PARAMS: Record<SortOption, { sort: string; order: string }> = {
  newest: { sort: 'created_at', order: 'desc' },
  oldest: { sort: 'created_at', order: 'asc' },
  name_asc: { sort: 'name', order: 'asc' },
  producer_asc: { sort: 'producer', order: 'asc' },
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
  const res = await fetch(`${BASE_URL}/wines/search?${params}`);
  if (!res.ok) throw new Error(`Search failed: ${res.status}`);
  return res.json() as Promise<SearchResponse>;
}

export async function curate(
  wineId: string,
  verified: boolean,
): Promise<{ wine_id: string; verified: boolean }> {
  const res = await fetch(`${BASE_URL}/curate`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ wine_id: wineId, verified }),
  });
  if (!res.ok) throw new Error(`Curate failed: ${res.status}`);
  return res.json() as Promise<{ wine_id: string; verified: boolean }>;
}

export async function deleteWine(wineId: string): Promise<void> {
  const res = await fetch(`${BASE_URL}/wines/${wineId}`, { method: 'DELETE' });
  if (!res.ok && res.status !== 404) throw new Error(`Delete failed: ${res.status}`);
}

export function absoluteImageUrl(relativeUrl: string): string {
  return `${BASE_URL}${relativeUrl}`;
}
