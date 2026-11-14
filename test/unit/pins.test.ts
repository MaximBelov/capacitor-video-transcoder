import { describe, expect, it } from 'vitest';

import {
  SDKS,
  assess,
  bump,
  compareVersions,
  decide,
  latestStable,
  readPin,
  superseded,
} from '../../scripts/check-pins.mjs';

const [media3] = SDKS;

describe('the Media3 pin', () => {
  it('is read from android/build.gradle', () => {
    expect(readPin(media3)).toMatch(/^\d+\.\d+\.\d+$/);
  });

  it('compares versions as numbers', () => {
    expect(compareVersions('1.9.3', '1.11.1')).toBeLessThan(0);
    expect(compareVersions('1.11.1', '1.11.1')).toBe(0);
    expect(compareVersions('2.0.0', '1.11.1')).toBeGreaterThan(0);
  });

  it('takes the newest stable version from Maven, passing over previews', () => {
    const metadata = `<metadata><versioning><latest>1.12.0-alpha02</latest><versions>
      <version>1.9.3</version><version>1.11.0-rc02</version><version>1.11.1</version>
      <version>1.10.0</version><version>1.12.0-alpha02</version></versions></versioning></metadata>`;
    expect(latestStable(metadata)).toBe('1.11.1');
    expect(() => latestStable('<versions><version>1.0.0-beta01</version></versions>')).toThrow();
  });

  it('moves the pin, and only the pin', () => {
    const files: Record<string, string> = {};
    const before =
      "x\n    media3Version = project.hasProperty('media3Version') ? rootProject.ext.media3Version : '1.11.1'\ny\n";
    const written = bump(media3, '1.11.1', '1.12.0', {
      read: () => before,
      write: (file: string, text: string) => (files[file] = text),
    });
    expect(written).toEqual(['android/build.gradle']);
    expect(files['android/build.gradle']).toBe(before.replace("'1.11.1'", "'1.12.0'"));
    expect(() => bump(media3, '1.10.0', '1.12.0', { read: () => before, write: () => undefined })).toThrow(
      /pins 1\.11\.1/,
    );
  });

  it('opens a pull request only when behind and not already proposed, and replaces an older one', () => {
    const behind = assess(media3, '1.11.1', '1.12.0');
    expect(behind.branch).toBe('pin-Media3-1.12.0');
    expect(behind.major).toBe(false);
    expect(assess(media3, '1.11.1', '2.0.0').major).toBe(true);
    expect(decide(behind, []).open).toBe(true);
    expect(decide(behind, [{ number: 3, title: behind.title, state: 'CLOSED', headRefName: behind.branch }]).open).toBe(
      false,
    );
    expect(decide(assess(media3, '1.11.1', '1.11.1'), []).open).toBe(false);
    const old = { number: 2, title: 'Take Media3 1.11.2', state: 'OPEN', headRefName: 'pin-Media3-1.11.2' };
    expect(superseded(behind, [old])).toEqual([old]);
  });
});
