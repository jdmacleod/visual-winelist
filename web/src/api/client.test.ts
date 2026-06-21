import { searchWines, curate, deleteWine, absoluteImageUrl } from './client';

const mockFetch = vi.fn();
vi.stubGlobal('fetch', mockFetch);

function makeOkResponse(body: unknown): Response {
  return {
    ok: true,
    status: 200,
    json: () => Promise.resolve(body),
  } as unknown as Response;
}

function makeErrorResponse(status: number): Response {
  return {
    ok: false,
    status,
    json: () => Promise.resolve({}),
  } as unknown as Response;
}

beforeEach(() => {
  vi.clearAllMocks();
});

test('searchWines returns parsed response', async () => {
  const body = { results: [], total: 0, verified_total: 0 };
  mockFetch.mockResolvedValueOnce(makeOkResponse(body));

  const result = await searchWines('cab', 1);
  expect(result).toEqual(body);
  expect(mockFetch).toHaveBeenCalledWith(expect.stringContaining('/wines/search'), undefined);
});

test('searchWines throws on non-ok response', async () => {
  mockFetch.mockResolvedValueOnce(makeErrorResponse(500));
  await expect(searchWines('cab', 1)).rejects.toThrow('Search failed: 500');
});

test('curate returns result on success', async () => {
  const body = { wine_id: 'abc', verified: true };
  mockFetch.mockResolvedValueOnce(makeOkResponse(body));

  const result = await curate('abc', true);
  expect(result).toEqual(body);
  expect(mockFetch).toHaveBeenCalledWith(
    expect.stringContaining('/curate'),
    expect.objectContaining({ method: 'POST' }),
  );
});

test('curate throws on non-ok response', async () => {
  mockFetch.mockResolvedValueOnce(makeErrorResponse(404));
  await expect(curate('abc', true)).rejects.toThrow('Curate failed: 404');
});

test('deleteWine resolves on 200', async () => {
  mockFetch.mockResolvedValueOnce(makeOkResponse(null));
  await expect(deleteWine('abc')).resolves.toBeUndefined();
});

test('deleteWine resolves on 404 (already deleted)', async () => {
  mockFetch.mockResolvedValueOnce(makeErrorResponse(404));
  await expect(deleteWine('abc')).resolves.toBeUndefined();
});

test('deleteWine throws on other non-ok status', async () => {
  mockFetch.mockResolvedValueOnce(makeErrorResponse(500));
  await expect(deleteWine('abc')).rejects.toThrow('Delete failed: 500');
});

test('absoluteImageUrl prepends BASE_URL', () => {
  expect(absoluteImageUrl('/wines/abc/image')).toBe('/wines/abc/image');
});
