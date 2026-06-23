import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import ImageCandidatePicker from './ImageCandidatePicker';
import type { ImageCandidate } from '../types/wine';

vi.mock('../api/client', () => ({
  fetchImageCandidates: vi.fn(),
  setImageFromUrl: vi.fn(),
}));

const { fetchImageCandidates, setImageFromUrl } = await import('../api/client');

function makeCandidate(overrides: Partial<ImageCandidate> = {}): ImageCandidate {
  return {
    url: 'https://cdn.example.com/img.jpg',
    thumbnail_url: 'https://cdn.example.com/thumb.jpg',
    title: 'Château Margaux 2018 - Vivino',
    source_url: 'https://www.vivino.com/wines/123',
    width: 300,
    height: 600,
    ...overrides,
  };
}

function mockResolved(candidates: ImageCandidate[], query = 'Château Margaux 2018 wine bottle') {
  vi.mocked(fetchImageCandidates).mockResolvedValue({ candidates, query });
}

const defaultProps = {
  wineId: 'test-wine-id',
  onSelect: vi.fn(),
  onCancel: vi.fn(),
  onSwitchToUpload: vi.fn(),
};

beforeEach(() => {
  vi.clearAllMocks();
});

test('shows searching spinner while loading', () => {
  vi.mocked(fetchImageCandidates).mockReturnValue(new Promise(() => {}));
  render(<ImageCandidatePicker {...defaultProps} />);
  expect(screen.getByText('Searching Brave…')).toBeInTheDocument();
});

test('shows candidates after successful fetch', async () => {
  mockResolved([makeCandidate()]);
  render(<ImageCandidatePicker {...defaultProps} />);
  await waitFor(() => {
    const img = document.querySelector('img[src="https://cdn.example.com/thumb.jpg"]');
    expect(img).not.toBeNull();
  });
});

test('populates query input from response', async () => {
  mockResolved([makeCandidate()], 'Château Margaux 2018 wine bottle');
  render(<ImageCandidatePicker {...defaultProps} />);
  await waitFor(() => {
    const input = screen.getByPlaceholderText('Search query…') as HTMLInputElement;
    expect(input.value).toBe('Château Margaux 2018 wine bottle');
  });
});

test('shows error state when fetchImageCandidates rejects', async () => {
  vi.mocked(fetchImageCandidates).mockRejectedValue(new Error('Network error'));
  render(<ImageCandidatePicker {...defaultProps} />);
  await waitFor(() => {
    expect(screen.getByText("Couldn't load candidates")).toBeInTheDocument();
  });
});

test('retry button in error state triggers a new fetch', async () => {
  vi.mocked(fetchImageCandidates)
    .mockRejectedValueOnce(new Error('Network error'))
    .mockResolvedValueOnce({ candidates: [makeCandidate()], query: 'test query' });

  render(<ImageCandidatePicker {...defaultProps} />);
  await waitFor(() => {
    expect(screen.getByRole('button', { name: /try again/i })).toBeInTheDocument();
  });

  const user = userEvent.setup();
  await user.click(screen.getByRole('button', { name: /try again/i }));

  await waitFor(() => {
    const img = document.querySelector('img[src="https://cdn.example.com/thumb.jpg"]');
    expect(img).not.toBeNull();
  });
  expect(vi.mocked(fetchImageCandidates)).toHaveBeenCalledTimes(2);
});

test('shows empty state when no candidates returned', async () => {
  mockResolved([]);
  render(<ImageCandidatePicker {...defaultProps} />);
  await waitFor(() => {
    expect(screen.getByText('No candidates found')).toBeInTheDocument();
  });
});

test('onSwitchToUpload called when upload link clicked in empty state', async () => {
  mockResolved([]);
  render(<ImageCandidatePicker {...defaultProps} />);
  await waitFor(() => screen.getByText(/upload a photo instead/i));

  const user = userEvent.setup();
  await user.click(screen.getByText(/upload a photo instead/i));
  expect(defaultProps.onSwitchToUpload).toHaveBeenCalled();
});

test('onCancel called when Cancel button clicked', async () => {
  mockResolved([makeCandidate()]);
  render(<ImageCandidatePicker {...defaultProps} />);
  await waitFor(() => screen.getByRole('button', { name: /cancel/i }));

  const user = userEvent.setup();
  await user.click(screen.getByRole('button', { name: /cancel/i }));
  expect(defaultProps.onCancel).toHaveBeenCalled();
});

test('selecting a candidate calls setImageFromUrl and onSelect', async () => {
  const candidate = makeCandidate();
  mockResolved([candidate]);
  vi.mocked(setImageFromUrl).mockResolvedValue({
    wine_id: 'test-wine-id',
    image_url: '/wines/test-wine-id/image',
  });

  render(<ImageCandidatePicker {...defaultProps} />);
  await waitFor(() => screen.getByRole('button', { name: /use image from/i }));

  const user = userEvent.setup();
  await user.click(screen.getByRole('button', { name: /use image from/i }));

  await waitFor(() => {
    expect(vi.mocked(setImageFromUrl)).toHaveBeenCalledWith('test-wine-id', candidate.url);
    expect(defaultProps.onSelect).toHaveBeenCalledWith('/wines/test-wine-id/image');
  });
});

test('shows image_expired error message on 404/expired error', async () => {
  const candidate = makeCandidate();
  mockResolved([candidate]);
  vi.mocked(setImageFromUrl).mockRejectedValue(new Error('image_expired'));

  render(<ImageCandidatePicker {...defaultProps} />);
  await waitFor(() => screen.getByRole('button', { name: /use image from/i }));

  const user = userEvent.setup();
  await user.click(screen.getByRole('button', { name: /use image from/i }));

  await waitFor(() => {
    expect(screen.getByText('This image is no longer available — try another')).toBeInTheDocument();
  });
});

test('shows generic upload error on non-expired failure', async () => {
  const candidate = makeCandidate();
  mockResolved([candidate]);
  vi.mocked(setImageFromUrl).mockRejectedValue(new Error('Upload failed: 500'));

  render(<ImageCandidatePicker {...defaultProps} />);
  await waitFor(() => screen.getByRole('button', { name: /use image from/i }));

  const user = userEvent.setup();
  await user.click(screen.getByRole('button', { name: /use image from/i }));

  await waitFor(() => {
    expect(screen.getByText('Upload failed — try another')).toBeInTheDocument();
  });
});

test('displays vintage extracted from title', async () => {
  mockResolved([makeCandidate({ title: 'Opus One 2019 - Wine.com' })]);
  render(<ImageCandidatePicker {...defaultProps} />);
  await waitFor(() => screen.getByText('2019'));
  expect(screen.getByText('2019')).toBeInTheDocument();
});

test('displays source domain', async () => {
  mockResolved([makeCandidate({ source_url: 'https://www.vivino.com/wines/123' })]);
  render(<ImageCandidatePicker {...defaultProps} />);
  await waitFor(() => screen.getByText('www.vivino.com'));
  expect(screen.getByText('www.vivino.com')).toBeInTheDocument();
});

test('search button triggers re-fetch with custom query', async () => {
  mockResolved([makeCandidate()]);
  vi.mocked(fetchImageCandidates).mockResolvedValue({ candidates: [], query: 'my custom query' });

  render(<ImageCandidatePicker {...defaultProps} />);
  await waitFor(() => {
    expect(vi.mocked(fetchImageCandidates)).toHaveBeenCalledTimes(1);
  });

  const input = screen.getByPlaceholderText('Search query…');
  const user = userEvent.setup();
  await user.clear(input);
  await user.type(input, 'my custom query');
  await user.click(screen.getByRole('button', { name: /^search$/i }));

  await waitFor(() => {
    expect(vi.mocked(fetchImageCandidates)).toHaveBeenCalledTimes(2);
    expect(vi.mocked(fetchImageCandidates)).toHaveBeenLastCalledWith(
      'test-wine-id',
      'my custom query',
    );
  });
});
