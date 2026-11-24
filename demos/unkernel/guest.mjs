import { createKernel } from 'unkernel';

export const psiPath = '/tmp/psi';

export async function bootPsi(guestBytes) {
  // Use the embedded BusyBox image, with no network or persistent storage.
  const vm = await createKernel({ mounts: { '/mnt/demo': { psi: guestBytes } } });
  try {
    const { exitCode, stderr } = await vm.exec('/bin/sh', [
      '-c', 'cp /mnt/demo/psi /tmp/psi && chmod 755 /tmp/psi',
    ]);
    if (exitCode !== 0) throw new Error(`Installing psi in the guest: ${stderr}`);
    return vm;
  } catch (error) {
    await vm.stop();
    throw error;
  }
}
