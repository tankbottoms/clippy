export interface WiperState {
  countdown: number | null;
  paused: boolean;
}

export class Wiper {
  private countdown: number | null = null;
  private paused = false;
  private timer: ReturnType<typeof setInterval> | null = null;
  private delay: number;
  private onWipe: () => void;
  private onTick: (state: WiperState) => void;

  constructor(
    delay: number,
    onWipe: () => void,
    onTick: (state: WiperState) => void,
  ) {
    this.delay = delay;
    this.onWipe = onWipe;
    this.onTick = onTick;
  }

  startCountdown(): void {
    this.stopCountdown();
    this.countdown = this.delay;
    this.paused = false;
    this.onTick(this.getState());

    this.timer = setInterval(() => {
      if (this.paused || this.countdown === null) return;

      this.countdown--;
      this.onTick(this.getState());

      if (this.countdown <= 0) {
        this.stopCountdown();
        this.onWipe();
      }
    }, 1000);
  }

  stopCountdown(): void {
    if (this.timer) {
      clearInterval(this.timer);
      this.timer = null;
    }
    this.countdown = null;
    this.paused = false;
  }

  pause(): void {
    if (this.countdown !== null) {
      this.paused = true;
      this.onTick(this.getState());
    }
  }

  resume(): void {
    if (this.countdown !== null) {
      this.paused = false;
      this.onTick(this.getState());
    }
  }

  getState(): WiperState {
    return { countdown: this.countdown, paused: this.paused };
  }

  updateDelay(newDelay: number): void {
    this.delay = newDelay;
  }
}
