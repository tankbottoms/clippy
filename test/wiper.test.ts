import { describe, test, expect } from "bun:test";
import { Wiper } from "../src/wiper";

describe("Wiper", () => {
  test("initial state has no countdown", () => {
    const wiper = new Wiper(5, () => {}, () => {});
    const state = wiper.getState();

    expect(state.countdown).toBeNull();
    expect(state.paused).toBe(false);
  });

  test("startCountdown sets countdown to delay", () => {
    const wiper = new Wiper(5, () => {}, () => {});
    wiper.startCountdown();
    const state = wiper.getState();

    expect(state.countdown).toBe(5);
    expect(state.paused).toBe(false);

    wiper.stopCountdown();
  });

  test("stopCountdown clears countdown", () => {
    const wiper = new Wiper(5, () => {}, () => {});
    wiper.startCountdown();
    wiper.stopCountdown();
    const state = wiper.getState();

    expect(state.countdown).toBeNull();
    expect(state.paused).toBe(false);
  });

  test("pause sets paused flag", () => {
    const wiper = new Wiper(5, () => {}, () => {});
    wiper.startCountdown();
    wiper.pause();
    const state = wiper.getState();

    expect(state.paused).toBe(true);
    expect(state.countdown).toBe(5);

    wiper.stopCountdown();
  });

  test("resume clears paused flag", () => {
    const wiper = new Wiper(5, () => {}, () => {});
    wiper.startCountdown();
    wiper.pause();
    wiper.resume();
    const state = wiper.getState();

    expect(state.paused).toBe(false);

    wiper.stopCountdown();
  });

  test("updateDelay changes the delay value", () => {
    const wiper = new Wiper(5, () => {}, () => {});
    wiper.updateDelay(10);
    wiper.startCountdown();
    const state = wiper.getState();

    expect(state.countdown).toBe(10);

    wiper.stopCountdown();
  });

  test("onTick is called on startCountdown", () => {
    let tickCount = 0;
    const wiper = new Wiper(5, () => {}, () => { tickCount++; });
    wiper.startCountdown();

    expect(tickCount).toBe(1);

    wiper.stopCountdown();
  });

  test("countdown decrements and fires onWipe", async () => {
    let wiped = false;
    const ticks: number[] = [];

    const wiper = new Wiper(
      2,
      () => { wiped = true; },
      (state) => { if (state.countdown !== null) ticks.push(state.countdown); },
    );

    wiper.startCountdown();

    // Wait for countdown to complete (2s + margin)
    await new Promise((resolve) => setTimeout(resolve, 2500));

    expect(wiped).toBe(true);
    expect(ticks).toContain(2);
    expect(ticks).toContain(1);
  });
});
