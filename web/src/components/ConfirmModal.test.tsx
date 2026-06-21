import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import ConfirmModal from './ConfirmModal';

const defaultProps = {
  title: 'Delete Wine',
  message: 'This action cannot be undone.',
  onConfirm: vi.fn(),
  onCancel: vi.fn(),
};

beforeEach(() => {
  vi.clearAllMocks();
});

test('renders title, message, and buttons', () => {
  render(<ConfirmModal {...defaultProps} />);
  expect(screen.getByText('Delete Wine')).toBeInTheDocument();
  expect(screen.getByText('This action cannot be undone.')).toBeInTheDocument();
  expect(screen.getByRole('button', { name: 'Cancel' })).toBeInTheDocument();
  expect(screen.getByRole('button', { name: 'Confirm' })).toBeInTheDocument();
});

test('calls onCancel when Escape key is pressed', async () => {
  const user = userEvent.setup();
  render(<ConfirmModal {...defaultProps} />);
  await user.keyboard('{Escape}');
  expect(defaultProps.onCancel).toHaveBeenCalledOnce();
});

test('calls onCancel when backdrop is clicked', async () => {
  const user = userEvent.setup();
  render(<ConfirmModal {...defaultProps} />);
  const backdrop = document.querySelector('[aria-hidden="true"]') as HTMLElement;
  await user.click(backdrop);
  expect(defaultProps.onCancel).toHaveBeenCalledOnce();
});

test('disables both buttons and shows loading text when loading=true', () => {
  render(<ConfirmModal {...defaultProps} loading={true} />);
  expect(screen.getByRole('button', { name: 'Cancel' })).toBeDisabled();
  expect(screen.getByRole('button', { name: 'Deleting…' })).toBeDisabled();
});

test('calls onConfirm when confirm button is clicked', async () => {
  const user = userEvent.setup();
  render(<ConfirmModal {...defaultProps} />);
  await user.click(screen.getByRole('button', { name: 'Confirm' }));
  expect(defaultProps.onConfirm).toHaveBeenCalledOnce();
});

test('uses custom confirmLabel', () => {
  render(<ConfirmModal {...defaultProps} confirmLabel="Yes, delete" />);
  expect(screen.getByRole('button', { name: 'Yes, delete' })).toBeInTheDocument();
});
