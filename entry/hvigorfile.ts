import { hapTasks } from '@ohos/hvigor-ohos-plugin';
import * as path from 'path';
import { execFileSync } from 'child_process';

function ensureCredentials(): void {
  const rootDir = path.resolve(__dirname, '..');
  const injectScript = path.resolve(rootDir, 'tools/ci/inject_credentials.py');
  try {
    execFileSync('python3', [injectScript], {
      cwd: rootDir,
      stdio: 'inherit'
    });
  } catch (e) {
    throw new Error('[hvigor-entry] Failed to inject credentials. Check local.properties or environment variables.');
  }
}

ensureCredentials();

export default {
  system: hapTasks,
  plugins: []
};

