import { test, expect } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';

const views = ['home', 'mynotes', 'library', 'admin'] as const;

test.describe('WCAG 2.1 AA 출시 스모크', () => {
  for (const view of views) {
    test(`${view} 화면에 심각하거나 치명적인 자동 접근성 위반이 없다`, async ({ page }) => {
      await page.goto('/');
      await page.waitForLoadState('domcontentloaded');
      await page.evaluate((target) => {
        const api = window as typeof window & { switchView?: (view: string) => void };
        api.switchView?.(target);
      }, view);
      await page.waitForTimeout(150);

      const result = await new AxeBuilder({ page })
        .withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa'])
        .analyze();
      const blockers = result.violations.filter((item) => item.impact === 'critical' || item.impact === 'serious');
      expect(blockers, JSON.stringify(blockers, null, 2)).toEqual([]);
    });
  }
});
