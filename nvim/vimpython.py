import vim 

def deleteLine():
    vim.command('normal dd')

"""
        :py print "Hello"               # displays a message
        :py vim.command(cmd)            # execute an Ex command
        :py w = vim.windows[n]          # gets window "n"
        :py cw = vim.current.window     # gets the current window
        :py b = vim.buffers[n]          # gets buffer "n"
        :py cb = vim.current.buffer     # gets the current buffer
        :py w.height = lines            # sets the window height
        :py w.cursor = (row, col)       # sets the window cursor position
        :py pos = w.cursor              # gets a tuple (row, col)
        :py name = b.name               # gets the buffer file name
        :py line = b[n]                 # gets a line from the buffer
        :py lines = b[n:m]              # gets a list of lines
        :py num = len(b)                # gets the number of lines
        :py b[n] = str                  # sets a line in the buffer
        :py b[n:m] = [str1, str2, str3] # sets a number of lines at once
        :py del b[n]                    # deletes a line
        :py del b[n:m]                  # deletes a number of lines
"""

