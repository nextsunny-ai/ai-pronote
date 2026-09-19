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

  test('확인창은 키보드 초점을 가두고 닫힌 뒤 시작 위치로 돌려준다', async ({ page }) => {
    await page.goto('/');
    const trigger = page.locator('#jobCenterToggle');
    await trigger.focus();
    await page.evaluate(() => {
      const api = window as typeof window & {
        __pronoteAskConfirmation: (options: Record<string, unknown>) => Promise<boolean>;
      };
      void api.__pronoteAskConfirmation({ title: '키보드 확인', message: '초점 검사', confirmLabel: '확인' });
    });
    const dialog = page.getByRole('dialog', { name: '키보드 확인' });
    await expect(dialog).toBeVisible();
    await expect(dialog.getByRole('button', { name: '확인' })).toBeFocused();
    await page.keyboard.press('Tab');
    await expect(dialog.getByRole('button', { name: '닫기' })).toBeFocused();
    await page.keyboard.press('Shift+Tab');
    await expect(dialog.getByRole('button', { name: '확인' })).toBeFocused();
    await page.keyboard.press('Escape');
    await expect(dialog).toBeHidden();
    await expect(trigger).toBeFocused();
  });

  for (const size of [
    { name: '휴대폰 세로', width: 390, height: 844 },
    { name: '아이패드 세로', width: 768, height: 1024 },
    { name: '노트북 200% 확대 대응', width: 640, height: 450 },
  ]) {
    test(`${size.name}에서 메뉴와 노트가 화면 밖으로 밀리지 않는다`, async ({ page }) => {
      await page.setViewportSize({ width: size.width, height: size.height });
      await page.goto('/');
      const menu = page.locator('#mobileMenuBtn');
      await expect(menu).toBeVisible();
      await menu.click();
      await expect(page.locator('.sidebar')).toBeInViewport();
      await page.locator('.nav-item[data-demo="result-mynote"]').click();
      await expect(page.locator('#mynoteBlock')).toBeVisible();
      const overflow = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
      expect(overflow).toBeLessThanOrEqual(1);
    });
  }
});
