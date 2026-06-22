import { render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import App from './App';
import type { WineRecord, SearchResponse } from './types/wine';

vi.mock('./api/client', () => ({
  searchWines: vi.fn(),
  curate: vi.fn(),
  deleteWine: vi.fn(),
  absoluteImageUrl: (url: string) => url,
}));

const { searchWines, curate, deleteWine } = await import('./api/client');

function makeWine(overrides: Partial<WineRecord> = {}): WineRecord {
  return {
    wine_id: 'wine-1',
    name: 'Test Wine',
    producer: null,
    vintage: null,
    variety: null,
    appellation: null,
    tasting_note: null,
    pairings: [],
    verified: false,
    image_url: null,
    ...overrides,
  };
}

function makeResponse(wines: WineRecord[], verified_total = 0, total?: number): SearchResponse {
  return {
    results: wines,
    total: total ?? wines.length,
    page: 1,
    page_size: 20,
    verified_total,
  };
}

beforeEach(() => {
  vi.clearAllMocks();
});

test('renders wine list after loading', async () => {
  vi.mocked(searchWines).mockResolvedValue(makeResponse([makeWine()]));
  render(<App />);
  await waitFor(() => {
    expect(screen.getByRole('button', { name: /Test Wine/ })).toBeInTheDocument();
  });
  expect(screen.getByText('1 wine in cache')).toBeInTheDocument();
});

test('handleVerify increments verified_total when marking unverified wine as verified', async () => {
  const user = userEvent.setup();
  const wine = makeWine({ verified: false });
  vi.mocked(searchWines).mockResolvedValue(makeResponse([wine], 0));
  vi.mocked(curate).mockResolvedValueOnce({ ...wine, verified: true });

  render(<App />);
  await waitFor(() => screen.getByRole('button', { name: /Test Wine/ }));

  await user.click(screen.getByRole('button', { name: /Test Wine/ }));
  await user.click(screen.getByRole('button', { name: /mark verified/i }));

  await waitFor(() => {
    expect(screen.getByText(/1 verified/)).toBeInTheDocument();
  });
});

test('handleVerify decrements verified_total when unverifying a verified wine', async () => {
  const user = userEvent.setup();
  const wine = makeWine({ verified: true });
  vi.mocked(searchWines).mockResolvedValue(makeResponse([wine], 1));
  vi.mocked(curate).mockResolvedValueOnce({ ...wine, verified: false });

  render(<App />);
  await waitFor(() => screen.getByRole('button', { name: /Test Wine/ }));

  await user.click(screen.getByRole('button', { name: /Test Wine/ }));
  await user.click(screen.getByRole('button', { name: /unverify/i }));

  await waitFor(() => {
    expect(screen.queryByText(/1 verified/)).not.toBeInTheDocument();
  });
});

test('handleDelete opens the confirm modal', async () => {
  const user = userEvent.setup();
  vi.mocked(searchWines).mockResolvedValue(makeResponse([makeWine()]));

  render(<App />);
  await waitFor(() => screen.getByRole('button', { name: /Test Wine/ }));

  await user.click(screen.getByRole('button', { name: /Test Wine/ }));
  await user.click(screen.getByRole('button', { name: /^delete$/i }));

  expect(screen.getByRole('dialog', { name: /delete wine/i })).toBeInTheDocument();
});

test('handleConfirmDelete calls deleteWine and refetches wines', async () => {
  const user = userEvent.setup();
  vi.mocked(searchWines).mockResolvedValue(makeResponse([makeWine()]));
  vi.mocked(deleteWine).mockResolvedValue(undefined as never);

  render(<App />);
  await waitFor(() => screen.getByRole('button', { name: /Test Wine/ }));

  await user.click(screen.getByRole('button', { name: /Test Wine/ }));
  await user.click(screen.getByRole('button', { name: /^delete$/i }));

  const confirmDialog = screen.getByRole('dialog', { name: /delete wine/i });
  await user.click(within(confirmDialog).getByRole('button', { name: /^delete$/i }));

  await waitFor(() => {
    expect(vi.mocked(deleteWine)).toHaveBeenCalledWith('wine-1');
  });
  expect(vi.mocked(searchWines).mock.calls.length).toBeGreaterThan(1);
});

test('changing status filter resets page to 1', async () => {
  const user = userEvent.setup();
  vi.mocked(searchWines).mockResolvedValue(makeResponse([makeWine()], 0, 100));

  render(<App />);
  await waitFor(() => screen.getByRole('button', { name: /next/i }));

  await user.click(screen.getByRole('button', { name: /next/i }));
  await user.click(screen.getByRole('button', { name: /^verified$/i }));

  await waitFor(() => {
    const calls = vi.mocked(searchWines).mock.calls;
    const last = calls.at(-1)!;
    expect(last[1]).toBe(1);
    expect(last[3]).toBe('verified');
  });
});

test('shows fetchError banner when searchWines rejects', async () => {
  vi.mocked(searchWines).mockRejectedValue(new Error('backend down'));
  render(<App />);
  await waitFor(() => {
    expect(screen.getByText('backend down')).toBeInTheDocument();
  });
});

test('shows actionError when deleteWine rejects', async () => {
  const user = userEvent.setup();
  vi.mocked(searchWines).mockResolvedValue(makeResponse([makeWine()]));
  vi.mocked(deleteWine).mockRejectedValue(new Error('Delete failed'));

  render(<App />);
  await waitFor(() => screen.getByRole('button', { name: /Test Wine/ }));

  await user.click(screen.getByRole('button', { name: /Test Wine/ }));
  await user.click(screen.getByRole('button', { name: /^delete$/i }));
  const confirmDialog = screen.getByRole('dialog', { name: /delete wine/i });
  await user.click(within(confirmDialog).getByRole('button', { name: /^delete$/i }));

  await waitFor(() => {
    expect(screen.getByText('Delete failed')).toBeInTheDocument();
  });
});

test('actionError clears when selected wine changes', async () => {
  const user = userEvent.setup();
  const wine1 = makeWine({ wine_id: 'wine-1', name: 'Wine One' });
  const wine2 = makeWine({ wine_id: 'wine-2', name: 'Wine Two' });
  vi.mocked(searchWines).mockResolvedValue(makeResponse([wine1, wine2]));
  vi.mocked(curate).mockRejectedValueOnce(new Error('Verify failed'));

  render(<App />);
  await waitFor(() => screen.getByRole('button', { name: /Wine One/ }));

  await user.click(screen.getByRole('button', { name: /Wine One/ }));
  await user.click(screen.getByRole('button', { name: /mark verified/i }));
  await waitFor(() => {
    expect(screen.getByText('Verify failed')).toBeInTheDocument();
  });

  await user.click(screen.getByRole('button', { name: /Wine Two/ }));
  expect(screen.queryByText('Verify failed')).not.toBeInTheDocument();
});

test('sort select includes "Verified First" option', async () => {
  vi.mocked(searchWines).mockResolvedValue(makeResponse([]));
  render(<App />);
  // The select renders immediately (before search resolves) so no waitFor needed.
  const select = screen.getByRole('combobox', { name: /sort/i });
  const options = Array.from((select as HTMLSelectElement).options).map((o) => o.text);
  expect(options).toContain('Verified First');
});

test('selecting "Verified First" sort calls searchWines with sort=verified', async () => {
  const user = userEvent.setup();
  vi.mocked(searchWines).mockResolvedValue(makeResponse([]));
  render(<App />);

  const select = screen.getByRole('combobox', { name: /sort/i });
  await user.selectOptions(select, 'verified');

  await waitFor(() => {
    const calls = vi.mocked(searchWines).mock.calls;
    const last = calls.at(-1)!;
    // searchWines(query, page, pageSize, statusFilter, sortOption)
    expect(last[4]).toBe('verified');
  });
});

test('default sort is not verified on fresh render', () => {
  vi.mocked(searchWines).mockResolvedValue(makeResponse([]));
  render(<App />);
  const select = screen.getByRole('combobox', { name: /sort/i }) as HTMLSelectElement;
  expect(select.value).not.toBe('verified');
});
