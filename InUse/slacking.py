import pyautogui
import time
import random

def get_user_input():
    default_count = 30
    default_sleep_duration = 5  # Default sleep duration in minutes

    count_input = input(f"Enter the number of iterations (default is {default_count}): ")
    count = int(count_input) if count_input.strip() else default_count

    sleep_input = input(f"Enter the sleep duration in minutes (default is {default_sleep_duration}): ")
    sleep_minutes = int(sleep_input) if sleep_input.strip() else default_sleep_duration
    sleep_duration = sleep_minutes * 60  # Convert minutes to seconds

    return count, sleep_duration

def main():
    pyautogui.size()  # Printing screen size information
    count, sleep_duration = get_user_input()

    while count > 0:
        x = random.randrange(pyautogui.size().width)
        y = random.randrange(pyautogui.size().height)
        count -= 1
        print(f"Moving to: ({x}, {y}), Remaining iterations: {count}")
        pyautogui.moveTo(x, y, 3)
        pyautogui.click(button='right')
        time.sleep(sleep_duration)

if __name__ == "__main__":
    main()
