import { createKernel, wispBackend } from 'unkernel';

export const psiPath = '/tmp/psi';

export async function bootPsi(guestBytes, { relay, caBytes } = {}) {
  const files = { psi: guestBytes };
  if (relay) {
    if (new URL(relay).protocol !== 'wss:' || !caBytes?.length) {
      throw new Error('Network mode requires a secure Wisp relay and CA bundle.');
    }
    files['ca-bundle.crt'] = caBytes;
  }
  const vm = await createKernel({
    mounts: { '/mnt/demo': files },
    ...(relay ? { net: wispBackend(relay) } : {}),
  });
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
