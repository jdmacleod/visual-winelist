import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import WineDetailPanel from './WineDetailPanel';
import type { WineRecord } from '../types/wine';

vi.mock('../api/client', () => ({
  patchWine: vi.fn(),
  uploadWineImage: vi.fn(),
  absoluteImageUrl: (url: string) => url,
}));

// Import after vi.mock so we get the mocked versions.
const { patchWine, uploadWineImage } = await import('../api/client');

function makeWine(overrides: Partial<WineRecord> = {}): WineRecord {
  return {
    wine_id: 'test-wine-id',
    name: 'Château Test',
    producer: 'Test Winery',
    vintage: '2020',
    variety: 'Pinot Noir',
    appellation: 'Burgundy',
    tasting_note: null,
    pairings: [],
    verified: false,
    image_url: null,
    ...overrides,
  };
}

const defaultProps = {
  onClose: vi.fn(),
  onVerify: vi.fn(),
  onDelete: vi.fn(),
  onUpdate: vi.fn(),
  onImageUpdate: vi.fn(),
  loading: false,
  actionError: null,
};

beforeEach(() => {
  vi.clearAllMocks();
});

test('renders wine name and details', () => {
  render(<WineDetailPanel {...defaultProps} wine={makeWine()} />);
  expect(screen.getByText('Château Test')).toBeInTheDocument();
  expect(screen.getByText('Test Winery')).toBeInTheDocument();
});

test('startEdit populates draft with wine data', async () => {
  const user = userEvent.setup();
  render(<WineDetailPanel {...defaultProps} wine={makeWine()} />);
  await user.click(screen.getByRole('button', { name: /edit/i }));
  expect(screen.getByDisplayValue('Château Test')).toBeInTheDocument();
  expect(screen.getByDisplayValue('Test Winery')).toBeInTheDocument();
});

test('cancelEdit hides the edit form', async () => {
  const user = userEvent.setup();
  render(<WineDetailPanel {...defaultProps} wine={makeWine()} />);
  await user.click(screen.getByRole('button', { name: /edit/i }));
  await user.click(screen.getByRole('button', { name: /cancel/i }));
  expect(screen.queryByDisplayValue('Château Test')).not.toBeInTheDocument();
});

test('saveEdit shows validation error when name is empty', async () => {
  const user = userEvent.setup();
  render(<WineDetailPanel {...defaultProps} wine={makeWine()} />);
  await user.click(screen.getByRole('button', { name: /edit/i }));
  const nameInput = screen.getByDisplayValue('Château Test');
  await user.clear(nameInput);
  await user.click(screen.getByRole('button', { name: /save/i }));
  expect(screen.getByText('Wine name is required')).toBeInTheDocument();
  expect(patchWine).not.toHaveBeenCalled();
});

test('saveEdit success calls onUpdate and exits edit mode', async () => {
  const user = userEvent.setup();
  const updatedWine = makeWine({ name: 'New Name' });
  vi.mocked(patchWine).mockResolvedValueOnce(updatedWine);

  render(<WineDetailPanel {...defaultProps} wine={makeWine()} />);
  await user.click(screen.getByRole('button', { name: /edit/i }));
  const nameInput = screen.getByDisplayValue('Château Test');
  await user.clear(nameInput);
  await user.type(nameInput, 'New Name');
  await user.click(screen.getByRole('button', { name: /save/i }));

  await waitFor(() => {
    expect(defaultProps.onUpdate).toHaveBeenCalledWith(updatedWine);
  });
  expect(screen.queryByDisplayValue('New Name')).not.toBeInTheDocument();
});

test('handleFileChange shows error for files over 10 MB without uploading', async () => {
  const user = userEvent.setup();
  render(<WineDetailPanel {...defaultProps} wine={makeWine()} />);

  const bigFile = new File([new ArrayBuffer(10 * 1024 * 1024 + 1)], 'big.jpg', {
    type: 'image/jpeg',
  });
  const fileInput = document.querySelector('input[type="file"]') as HTMLInputElement;
  await user.upload(fileInput, bigFile);

  expect(screen.getByText('Image must be under 10 MB')).toBeInTheDocument();
  expect(uploadWineImage).not.toHaveBeenCalled();
});

test('saveEdit shows error when patchWine network call fails', async () => {
  const user = userEvent.setup();
  vi.mocked(patchWine).mockRejectedValueOnce(new Error('Network error'));

  render(<WineDetailPanel {...defaultProps} wine={makeWine()} />);
  await user.click(screen.getByRole('button', { name: /edit/i }));
  await user.click(screen.getByRole('button', { name: /save/i }));

  await waitFor(() => {
    expect(screen.getByText('Network error')).toBeInTheDocument();
  });
  expect(defaultProps.onUpdate).not.toHaveBeenCalled();
});

test('uploadWineImage shows error when upload network call fails', async () => {
  const user = userEvent.setup();
  vi.mocked(uploadWineImage).mockRejectedValueOnce(new Error('Upload failed'));

  render(<WineDetailPanel {...defaultProps} wine={makeWine()} />);

  const validFile = new File([new ArrayBuffer(1024)], 'bottle.jpg', {
    type: 'image/jpeg',
  });
  const fileInput = document.querySelector('input[type="file"]') as HTMLInputElement;
  await user.upload(fileInput, validFile);

  await waitFor(() => {
    expect(screen.getByText('Upload failed')).toBeInTheDocument();
  });
});

test('uploadWineImage success calls onImageUpdate', async () => {
  const user = userEvent.setup();
  vi.mocked(uploadWineImage).mockResolvedValueOnce({
    wine_id: 'test-wine-id',
    image_url: '/wines/test-wine-id/image',
  });

  render(<WineDetailPanel {...defaultProps} wine={makeWine()} />);

  const validFile = new File([new ArrayBuffer(1024)], 'bottle.jpg', {
    type: 'image/jpeg',
  });
  const fileInput = document.querySelector('input[type="file"]') as HTMLInputElement;
  await user.upload(fileInput, validFile);

  await waitFor(() => {
    expect(defaultProps.onImageUpdate).toHaveBeenCalledWith(
      'test-wine-id',
      expect.stringContaining('/wines/test-wine-id/image'),
    );
  });
});

test('onVerify called when Mark verified button is clicked', async () => {
  const user = userEvent.setup();
  render(<WineDetailPanel {...defaultProps} wine={makeWine({ verified: false })} />);
  await user.click(screen.getByRole('button', { name: /mark verified/i }));
  expect(defaultProps.onVerify).toHaveBeenCalledWith(true);
});

test('onDelete called when Delete button is clicked', async () => {
  const user = userEvent.setup();
  render(<WineDetailPanel {...defaultProps} wine={makeWine()} />);
  await user.click(screen.getByRole('button', { name: /delete/i }));
  expect(defaultProps.onDelete).toHaveBeenCalled();
});
