;;; jupyter-ascending.el --- Edit Jupyter Notebooks in plain text -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2025 Duncan Britt
;;
;; Author: Duncan Britt
;; Contact: https://github.com/Duncan-Britt/jupyter-ascending/issues
;; URL: https://github.com/Duncan-Britt/jupyter-ascending
;; Version: 0.1.0
;; Keywords: tools, jupyter, notebook, python
;; Package-Requires: ((emacs "29.4"))

;; This file is NOT part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:
;; ┌─────────┐
;; │ Summary │
;; └─────────┘
;; The Jupyter Ascending package facilitates editing and executing
;; code in a Jupyter Python notebook from an ordinary Python buffer.
;; It does this by providing commands which utilize the Jupytext and
;; Jupyter Ascending command line tools for
;; - rendering .ipynb notebooks as standard Python source files,
;; - synchronizing the state of the 2 files, and
;; - executing code in the Jupyter notebook.
;; This allows users to work with Jupyter Python notebooks and make
;; use of all the features they would normally have when editing
;; Python code, such as code completion, linting, etc.

;; ┌──────────┐
;; │ Features │
;; └──────────┘
;; - Synchronization: Editing and saving the Python buffer
;;   automatically updates the Jupyter notebook
;; - Cell execution commands: Run individual cells or the entire
;;   notebook
;; - Navigation tools: Jump between cells with simple commands
;; - Cell management: Create new cells and toggle between code and
;;   markdown types
;; - Enhanced markdown editing:
;;   - Edit markdown cells in dedicated markdown buffers (similar to
;;     Org mode's special edit mode)
;;   - Automatic comment insertion when pressing return in markdown
;;     cells
;; - Setup utilities: Commands for starting Jupyter notebooks and
;;   creating synchronized file pairs

;; ┌─────────────┐
;; │ Limitations │
;; └─────────────┘
;; This package only works with Python notebooks because the Jupyter
;; Ascending command line tool only supports Python notebooks.  See
;; here: https://github.com/imbue-ai/jupyter_ascending/issues/25

;; ┌──────────────┐
;; │ Installation │
;; └──────────────┘
;; The following dependencies must be installed, in addition to Jupyter:
;; pip install jupyter_ascending &&
;; python3 -m jupyter nbextension    install jupyter_ascending --sys-prefix --py && \
;; python3 -m jupyter nbextension     enable jupyter_ascending --sys-prefix --py && \
;; python3 -m jupyter serverextension enable jupyter_ascending --sys-prefix --py
;;
;; Example use-package installation
;; (use-package jupyter-ascending
;;   :ensure t
;;   :hook (python-mode . (lambda ()
;;                          (when (and buffer-file-name
;;                                     (string-match-p "\\.sync\\.py\\'" buffer-file-name))
;;                            (jupyter-ascending-mode 1))))
;;   :bind (:map jupyter-ascending-mode-map
;;               ("C-c C-k" . jupyter-ascending-execute-line)
;;               ("C-c C-a" . jupyter-ascending-execute-all)
;;               ("C-c C-n" . jupyter-ascending-next-cell)
;;               ("C-c C-p" . jupyter-ascending-previous-cell)
;;               ("C-c t" . jupyter-ascending-cycle-cell-type)
;;               ("C-c '" . jupyter-ascending-edit-markdown-cell)))
;;
;; ┌───────┐
;; │ Usage │
;; └───────┘
;; Create a notebook pair with:
;;     M-x `jupyter-ascending-create-notebook-pair' RET example RET
;; Or, equivalently
;;     python3 -m jupyter_ascending.scripts.make_pair --base example
;; This creates synced files: example.sync.py and example.sync.ipynb
;;
;; Start jupyter and open the notebook:
;;     With example.sync.py open,
;;     M-x `jupyter-ascending-start-notebook'
;; Or, equivalently,
;;     python3 -m jupyter notebook example.sync.ipynb
;;
;; If you have an existing jupyter notebook, create a python file from it,
;;     M-x `jupyter-ascending-convert-notebook' RET example.ipynb RET
;; Or, equivalently,
;;     jupytext --to py:percent <file_name>
;; and then add the .sync suffix to both files
;;
;;; Code:
;; For markdown-mode-map and markdown-mode
(declare-function markdown-mode "markdown-mode" ())
(defvar markdown-mode-map)

;; For dired-get-filename
(declare-function dired-get-filename "dired" (&optional localp no-error-if-not-filep))

(defgroup jupyter-ascending nil
  "Edit Jupyter notebooks in Emacs using jupyter_ascending."
  :group 'tools
  :prefix "jupyter-ascending-")

(defcustom jupyter-ascending-python-command "python3"
  "Python command used by jupyter ascending."
  :type 'string
  :group 'jupyter-ascending)

(defvar jupyter-ascending-mode-map (make-sparse-keymap)
  "Keymap for `jupyter-ascending-mode'.")

;; ┌──────────┐
;; │ Commands │
;; └──────────┘
(defun jupyter-ascending-sync-file ()
  "Sync the current buffer with its associated Jupyter notebook."
  (interactive)
  (when (called-interactively-p 'any)
    (save-buffer))
  (jupyter-ascending--run-jupyter-ascending-command
   "sync"
   "--filename" (buffer-file-name)))

(defun jupyter-ascending-execute-line ()
  "Execute the cell at current line in the associated Jupyter notebook."
  (interactive)
  (save-buffer)
  (jupyter-ascending--run-jupyter-ascending-command
   "execute"
   "--filename" (buffer-file-name)
   "--linenumber" (number-to-string (line-number-at-pos))))

(defun jupyter-ascending-execute-all ()
  "Execute all cells in the associated Jupyter notebook."
  (interactive)
  (save-buffer)
  (jupyter-ascending--run-jupyter-ascending-command
   "execute_all"
   "--filename" (buffer-file-name)))

;;;###autoload
(defun jupyter-ascending-start-notebook ()
  "Start a Jupyter notebook for the current file.
Assumes the notebook has the same name as the current file but
with .ipynb extension."
  (interactive)
  (let* ((current-file (buffer-file-name))
         (notebook-file (concat (file-name-sans-extension current-file) ".ipynb"))
         (default-directory (file-name-directory (expand-file-name current-file))))

    (unless (file-exists-p notebook-file)
      (error "Notebook file %s does not exist.  Run jupyter-ascending-init-file first" notebook-file))

    (async-shell-command
     (format "%s -m jupyter notebook %s"
             jupyter-ascending-python-command
             (shell-quote-argument (file-name-nondirectory notebook-file)))
     "*jupyter-notebook*")))

(defun jupyter-ascending-restart-notebook ()
  "Restart associated Jupyter notebook."
  (interactive)
  (save-buffer)
  (jupyter-ascending--run-jupyter-ascending-command
   "restart"
   "--filename" (buffer-file-name)))

(defvar jupyter-ascending-mode nil
  "Silences warning about reference to free variable.
`jupyter-ascending-mode'")

(defun jupyter-ascending-after-save-hook ()
  "Run after saving to sync with Jupyter notebook."
  (when jupyter-ascending-mode
    (jupyter-ascending-sync-file)))

(defun jupyter-ascending-next-cell ()
  "Move point to the next cell marked by '# %%' at the beginning of a line."
  (interactive)
  (end-of-line)
  (if (re-search-forward "^# %%" nil t)
      (beginning-of-line)
    (goto-char (point-max))
    (unless (bolp) (insert "\n"))
    (insert "\n# %%\n")
    (message "Created new code cell")))

(defun jupyter-ascending-previous-cell ()
  "Move point to the previous cell marked by '# %%' at the beginning of a line."
  (interactive)
  (let ((orig-point (point)))
    (beginning-of-line)
    (if (re-search-backward "^# %%" nil t)
        (beginning-of-line)
      (goto-char orig-point)
      (message "No previous cell found"))))

(defun jupyter-ascending-cycle-cell-type ()
  "Toggle the current cell between code and markdown type."
  (interactive)
  (save-excursion
    ;; Find the current cell header
    (let ((cell-start (save-excursion
                        (if (looking-at "^# %%")
                            (point)
                          (and (re-search-backward "^# %%" nil t)
                               (point))))))
      (if (not cell-start)
          (message "Not in a cell")
        (goto-char cell-start)
        (if (looking-at "^# %% \\[markdown\\]")
            ;; If it's a markdown cell, convert to code cell
            (progn
              (delete-region (point) (line-end-position))
              (insert "# %%")
              (message "Converted to code cell"))
          ;; If it's a code cell, convert to markdown cell
          (progn
            (delete-region (point) (line-end-position))
            (insert "# %% [markdown]")
            (message "Converted to markdown cell")))))))

(defun jupyter-ascending-markdown-RET ()
  "Handle RET key in markdown cells.
If in a markdown cell, insert a '#' comment marker with proper spacing.
Otherwise, use the default RET behavior."
  (interactive)
  (if (jupyter-ascending--in-markdown-cell-p)
      (progn
        (newline)
        (insert "# ")
        (set-marker (mark-marker) (point) (current-buffer)))
    (newline-and-indent)))

;;;###autoload
(defun jupyter-ascending-create-notebook-pair (base-name)
  "Create a synced pair of Jupyter notebook files using jupyter_ascending.
With BASE-NAME as the file prefix (without
extension), creates .sync.py and .sync.ipynb files."
  (interactive
   (list
    (read-string "Base name for notebook: ")))

  (let* ((default-directory (if (buffer-file-name)
                               (file-name-directory (buffer-file-name))
                             default-directory))
         (command (format "%s -m jupyter_ascending.scripts.make_pair --base %s"
                          jupyter-ascending-python-command
                          (shell-quote-argument base-name)))
         (buffer-name "*jupyter-ascending-create*"))

    (message "Creating notebook pair with base name: %s" base-name)
    (with-current-buffer (get-buffer-create buffer-name)
      (erase-buffer)
      (let ((proc (start-process "jupyter-ascending-create-notebook" buffer-name
                                 shell-file-name shell-command-switch command)))
        (set-process-sentinel
         proc
         (lambda (_process event)
           (if (string-match "finished" event)
               (message "Created Jupyter notebook pair: %s.sync.{py,ipynb}" base-name)
             (message "Error creating notebook pair: %s"
                      (with-current-buffer buffer-name (buffer-string))))
           ;; Optionally visit the new files
           (when (string-match "finished" event)
             (when (y-or-n-p "Open the Python file? ")
               (find-file (format "%s.sync.py" base-name))
               (jupyter-ascending-mode 1)))))))))

;;;###autoload
(defun jupyter-ascending-convert-notebook ()
  "Convert an existing Jupyter notebook to a synced pair with jupytext.
Renames both files with .sync infix."
  (interactive)
  (let* ((ipynb-file (cond
                      ;; If in dired and at an ipynb file
                      ((and (derived-mode-p 'dired-mode)
                            (dired-get-filename nil t)
                            (string-match "\\.ipynb$" (dired-get-filename nil t)))
                       (dired-get-filename nil t))
                      ;; If current buffer is an ipynb file
                      ((and (buffer-file-name)
                            (string-match "\\.ipynb$" (buffer-file-name)))
                       (buffer-file-name))
                      ;; Otherwise prompt with a file selector
                      (t (read-file-name "Select Jupyter notebook (.ipynb): " nil nil t nil
                                         (lambda (filename)
                                           (string-match "\\.ipynb$" filename))))))
         (ipynb-file (expand-file-name ipynb-file))
         (ipynb-dir (file-name-directory ipynb-file))
         (ipynb-base (file-name-sans-extension (file-name-nondirectory ipynb-file)))
         (py-file (expand-file-name (concat ipynb-base ".py") ipynb-dir))
         (sync-ipynb-file (expand-file-name (concat ipynb-base ".sync.ipynb") ipynb-dir))
         (sync-py-file (expand-file-name (concat ipynb-base ".sync.py") ipynb-dir))
         (buffer-name "*jupytext-convert*"))

    ;; Run jupytext to convert ipynb to py
    (message "Converting %s to Python..." ipynb-file)
    (with-current-buffer (get-buffer-create buffer-name)
      (erase-buffer)
      (let ((proc (start-process "jupytext" buffer-name
                                 "jupytext" "--to" "py:percent" ipynb-file)))
        (set-process-sentinel
         proc
         (lambda (_process event)
           (if (string-match "finished" event)
               (progn
                 (message "Converted %s to %s" ipynb-file py-file)
                 ;; Now rename files with .sync infix
                 (rename-file ipynb-file sync-ipynb-file t)
                 (rename-file py-file sync-py-file t)
                 (message "Created synced pair: %s and %s"
                          sync-ipynb-file sync-py-file)

                 ;; Optionally open the Python file
                 (when (y-or-n-p "Open the Python file? ")
                   (find-file sync-py-file)
                   (jupyter-ascending-mode 1)))
             (message "Error converting notebook: %s"
                      (with-current-buffer buffer-name (buffer-string))))))))))

;; ┌──────────────────┐
;; │ Markdown editing │
;; └──────────────────┘
(defvar-local jupyter-ascending--edit-marker nil
  "Marker for the original location in the source buffer.")

(defvar-local jupyter-ascending--edit-src-buffer nil
  "Buffer that contains the original markdown cell.")

(defvar-local jupyter-ascending--edit-cell-overlay nil
  "Overlay highlighting the cell being edited.")

(defun jupyter-ascending-save-src-buffer ()
  "Save the source buffer associated with this edit buffer."
  (interactive)
  (when (and jupyter-ascending--edit-src-buffer (buffer-live-p jupyter-ascending--edit-src-buffer))
    (let* ((cell-content (buffer-string))
           (src-buffer jupyter-ascending--edit-src-buffer)
           (overlay (buffer-local-value 'jupyter-ascending--edit-cell-overlay src-buffer))
           (saved-edit-buffer (current-buffer)))
      (with-current-buffer src-buffer
        (when (buffer-local-value 'jupyter-ascending--edit-cell-overlay src-buffer)
          (let ((start (overlay-start overlay))
                (end (overlay-end overlay)))
            (undo-boundary)
            (goto-char start)
            (delete-region start end)

            ;; Add the comment prefix to each line
            ;; Split content by lines, add comment prefix, then join
            (let ((commented-lines
                   (mapconcat (lambda (line) (concat "# " line))
                              (split-string cell-content "\n")
                              "\n")))
              (insert commented-lines))

            ;; Recreate the overlay for the new content
            (let ((new-end (point)))
              (delete-overlay overlay)
              (setq overlay (make-overlay start new-end))
              (overlay-put overlay 'face 'secondary-selection)
              (setq-local jupyter-ascending--edit-cell-overlay overlay)
              ;; Update overlay in edit buffer too
              (with-current-buffer saved-edit-buffer
                (setq-local jupyter-ascending--edit-cell-overlay overlay)))))

        (save-buffer)
        (jupyter-ascending-sync-file)))))

(defun jupyter-ascending-edit-markdown-cell ()
  "Edit the current markdown cell in a dedicated buffer."
  (interactive)
  (barf-if-buffer-read-only)
  (unless (jupyter-ascending--in-markdown-cell-p)
    (user-error "Not in a markdown cell"))

  ;; Find the cell boundaries
  (let* ((cell-start (save-excursion
                       (re-search-backward "^# %%" nil t)
                       (forward-line 1)
                       (point)))
         (cell-end (save-excursion
            (let ((next-cell (save-excursion
                               (and (re-search-forward "^# %%" nil t)
                                    (line-beginning-position)))))
              ;; Start from cell-start
              (goto-char cell-start)
              ;; Find the last line that starts with # before the next cell
              (let ((last-comment-line nil))
                (while (and (< (point) (or next-cell (point-max)))
                            (not (eobp)))
                  (when (looking-at "^#")
                    (setq last-comment-line (line-end-position)))
                  (forward-line 1))
                ;; If we found at least one comment line, use it as end
                ;; Otherwise fall back to next cell or point-max
                (or last-comment-line next-cell (point-max))))))
         (cell-content (jupyter-ascending--markdown-cell-content cell-start cell-end))
         (edit-buffer (generate-new-buffer (concat "*jupyter-ascending-markdown-edit*")))
         (src-buffer (current-buffer))
         (overlay (make-overlay cell-start cell-end)))

    ;; Set properties for the overlay
    (overlay-put overlay 'face 'secondary-selection)
      (setq jupyter-ascending--edit-cell-overlay overlay)

    ;; Create marker for the original position
    (setq jupyter-ascending--edit-marker (set-marker (make-marker) (point)))

    ;; Set up the edit buffer
    (with-current-buffer edit-buffer
      (markdown-mode)
      (insert cell-content)
      (goto-char (point-min))
      (set-buffer-modified-p nil)
      (setq-local jupyter-ascending--edit-src-buffer src-buffer)
      (setq-local jupyter-ascending--edit-cell-overlay overlay)

      (use-local-map (copy-keymap markdown-mode-map))
      (local-set-key (kbd "C-c C-c") #'jupyter-ascending-edit-markdown-finish)
      (local-set-key (kbd "C-c C-k") #'jupyter-ascending-edit-markdown-abort)
      (local-set-key (kbd "C-x C-s") #'jupyter-ascending-save-src-buffer)

  (setq header-line-format
        (substitute-command-keys
         "Edit markdown cell. \\[jupyter-ascending-edit-markdown-finish] to finish, \\[jupyter-ascending-edit-markdown-abort] to abort. \\[jupyter-ascending-save-src-buffer] to save source.")))

    (pop-to-buffer edit-buffer)))

(defun jupyter-ascending-edit-markdown-finish ()
  "Finish editing the markdown cell and update the original buffer."
  (interactive)
  (let ((edit-buffer (current-buffer))
        (cell-content (buffer-string))
        (src-buffer jupyter-ascending--edit-src-buffer)
        (overlay jupyter-ascending--edit-cell-overlay)
        (edit-window (selected-window)))

    (unless (and src-buffer (buffer-live-p src-buffer))
      (user-error "Source buffer gone, cannot finish editing"))

    ;; Insert the edited content back into the source buffer
    (with-current-buffer src-buffer
      (when (buffer-local-value 'jupyter-ascending--edit-cell-overlay src-buffer)
        (let ((overlay (buffer-local-value 'jupyter-ascending--edit-cell-overlay src-buffer))
              (start (overlay-start overlay))
              (end (overlay-end overlay)))
          (undo-boundary)
          (goto-char start)
          (delete-region start end)

          ;; Add the comment prefix to each line
          ;; Split content by lines, add comment prefix, then join
          (let ((commented-lines
                 (mapconcat (lambda (line) (concat "# " line))
                            (split-string cell-content "\n")
                            "\n")))
            (insert commented-lines))
          ;; Move cursor to the original position if possible
          (when (and jupyter-ascending--edit-marker (marker-buffer jupyter-ascending--edit-marker))
            (goto-char jupyter-ascending--edit-marker)
            (set-marker jupyter-ascending--edit-marker nil))

          ;; Clean up overlay
          (delete-overlay overlay)
          (setq jupyter-ascending--edit-cell-overlay nil))))

    ;; Find window displaying source buffer
    (let ((src-window (get-buffer-window src-buffer)))
      (if src-window
          ;; If source buffer is visible in a window, select it
          (select-window src-window)
        ;; Otherwise, switch to source buffer in the edit window
        (set-window-buffer edit-window src-buffer)))

    ;; Kill the edit buffer
    (let ((kill-buffer-query-functions nil))
      (kill-buffer edit-buffer)

      (delete-window edit-window))))

(defun jupyter-ascending-edit-markdown-abort ()
  "Abort editing the markdown cell."
  (interactive)
  (let ((edit-buffer (current-buffer))
        (src-buffer jupyter-ascending--edit-src-buffer)
        (overlay jupyter-ascending--edit-cell-overlay)
        (edit-window (selected-window)))

    ;; Go back to source buffer
    (when (and src-buffer (buffer-live-p src-buffer))
      (with-current-buffer src-buffer
        ;; Clean up overlay
        (when (and overlay (overlay-buffer overlay))
          (delete-overlay overlay)
          (setq jupyter-ascending--edit-cell-overlay nil))
        ;; Move cursor to the original position if possible
        (when (and jupyter-ascending--edit-marker (marker-buffer jupyter-ascending--edit-marker))
          (goto-char jupyter-ascending--edit-marker)
          (set-marker jupyter-ascending--edit-marker nil)))

      ;; Find window displaying source buffer
      (let ((src-window (get-buffer-window src-buffer)))
        (if src-window
            ;; If source buffer is visible in a window, select it
            (select-window src-window)
          ;; Otherwise, switch to source buffer in the edit window
          (set-window-buffer edit-window src-buffer))))

    ;; Kill the edit buffer
    (let ((kill-buffer-query-functions nil))
      (kill-buffer edit-buffer))

    (delete-window edit-window)))

;; ┌────────────┐
;; │ Minor mode │
;; └────────────┘
;;;###autoload
(define-minor-mode jupyter-ascending-mode
  "Minor mode for editing Jupyter notebooks with jupyter_ascending.

\\{jupyter-ascending-mode-map}"
  :lighter " JA"
  :keymap jupyter-ascending-mode-map
  :group 'jupyter-ascending
  (if jupyter-ascending-mode
      (progn
        (add-hook 'after-save-hook #'jupyter-ascending-after-save-hook nil t)
        (local-set-key (kbd "RET") 'jupyter-ascending-markdown-RET)
        (message "Jupyter-Ascending mode enabled"))
    (remove-hook 'after-save-hook #'jupyter-ascending-after-save-hook t)
    (local-unset-key (kbd "RET"))
    (message "Jupyter-Ascending mode disabled")))

;; ┌────────────────────┐
;; │ Internal Functions │
;; └────────────────────┘

(defun jupyter-ascending--markdown-cell-content (cell-start cell-end)
  "Return the markdown content between CELL-START and CELL-END."
  (let ((cell-content ""))
    (save-excursion
      (goto-char cell-start)
      (while (< (point) cell-end)
        (let ((line-start (line-beginning-position))
              (line-end (line-end-position)))
          (if (looking-at "^#\\s-?")
              ;; If line starts with # and optional space
              (let ((comment-end (match-end 0))
                    (line-content (buffer-substring-no-properties line-start line-end)))
                ;; Only add the part after the comment marker
                (setq cell-content
                      (concat cell-content
                              (substring line-content (- comment-end line-start))
                              "\n")))
            ;; If no comment marker (shouldn't happen in well-formed cells),
            ;; just add the line as-is
            (setq cell-content
                  (concat cell-content
                          (buffer-substring-no-properties line-start line-end)
                          "\n"))))
        (forward-line 1)))

    (when (string-match-p "\n\\'" cell-content)
      (setq cell-content (substring cell-content 0 -1)))
    cell-content))

(defun jupyter-ascending--run-jupyter-ascending-command (command &rest args)
  "Run a jupyter_ascending COMMAND with ARGS asynchronously."
  (let* ((proc-name "jupyter-ascending")
         (module-path (concat "jupyter_ascending.requests." command)))
    (message "Running: %s %s" jupyter-ascending-python-command (mapconcat #'identity args " "))
    (let ((proc (apply #'start-process
                       proc-name
                       "*jupyter-ascending*"  ; buffer to help with debugging
                       jupyter-ascending-python-command
                       (append (list "-m" module-path) args))))
      (set-process-sentinel
       proc
       (lambda (_process event)
         (if (string-match "finished" event)
             (message "Jupyter ascending `%s' completed successfully" command)
           (message "Jupyter command event: %s" event)))))))

(defun jupyter-ascending--in-markdown-cell-p ()
  "Return non-nil if point is within a markdown cell.
A markdown cell is defined by a line starting with '# %% [markdown]'."
  (save-excursion
    (let ((cell-start (save-excursion
                        (if (looking-at "^# %%")
                            (point)
                          (and (re-search-backward "^# %%" nil t)
                               (point)))))
          (next-cell-start (save-excursion
                             (forward-line)
                             (and (re-search-forward "^# %%" nil t)
                                  (line-beginning-position)))))
      (when cell-start
        (goto-char cell-start)
        (and (looking-at "^# %% \\[markdown\\]")
             (or (not next-cell-start)
                 (< (point) next-cell-start)))))))

(provide 'jupyter-ascending)
;;; jupyter-ascending.el ends here
