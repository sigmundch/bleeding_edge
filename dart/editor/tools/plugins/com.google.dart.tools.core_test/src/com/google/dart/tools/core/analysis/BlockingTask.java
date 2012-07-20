package com.google.dart.tools.core.analysis;

public class BlockingTask extends Task {

  private Object lock = new Object();
  private boolean blocked = true;
  private boolean performed = false;

  @Override
  public boolean isBackgroundAnalysis() {
    return false;
  }

  @Override
  public boolean isPriority() {
    return false;
  }

  @Override
  public void perform() {
    synchronized (lock) {
      while (blocked) {
        try {
          lock.wait();
        } catch (InterruptedException e) {
          //$FALL-THROUGH$
        }
      }
      performed = true;
      lock.notifyAll();
    }
  }

  @Override
  public String toString() {
    return getClass().getSimpleName() + "[blocking," + hashCode() + "]";
  }

  public boolean wasPerformed() {
    synchronized (lock) {
      return performed;
    }
  }

  void unblock() {
    synchronized (lock) {
      blocked = false;
      lock.notifyAll();
    }
  }

  boolean waitForPerformed(long milliseconds) {
    long end = System.currentTimeMillis() + milliseconds;
    synchronized (lock) {
      while (!performed) {
        long delta = end - System.currentTimeMillis();
        if (delta <= 0) {
          return false;
        }
        try {
          lock.wait(delta);
        } catch (InterruptedException e) {
          //$FALL-THROUGH$
        }
      }
      return true;
    }
  }
}