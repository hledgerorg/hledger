;; Helper for managing issue links in markdown.
;; See also markdown-mode's interactive C-c C-c c and C-c C-c u.

(defun md-issue-refs (beginning end)
  "Scan the selected region for markdown shortcut reference links
   of the form [#NUM] and add/update link reference definitions
   at the end, pointing to the corresponding github issues.
   Removes any pre-existing #NUM link reference definitions from the region.
   This is useful eg for maintaining link reference definitions in release notes.
   XXX Currently hardcoded for the hledgerorg/hledger repo.
   XXX Does not work if parts of region are collapsed as with TAB in markdown-mode.
   "
  (interactive "r")
  (setq beginning (min beginning end))
  (setq end (max beginning end))
  (let ((nums '()))
    (save-excursion
      (save-restriction
        (widen)      ;; XXX trying to make it work with collapsed regions
        (narrow-to-region beginning end)

        ;; Remove pre-existing numeric link reference definitions
        (goto-char (point-min))
        (while (re-search-forward "^\\[#[0-9]+\\]:" nil t) (kill-whole-line))

        ;; Scan the region and collect link IDs
        (goto-char (point-min))
        (while (and (< (point) (point-max))
                    (search-forward-regexp "\\[#\\([0-9]+\\)\\]" nil t))
          (setq nums (cons (match-string 1) nums)))
        (setq nums (sort nums #'string-version-lessp))
        (setq max-length (apply #'max (cons 0 (mapcar #'length nums))))

        ;; Generate link reference definitions, with urls aligned
        (goto-char (point-max))
        (let ((fmt (concat "%-" (number-to-string (+ 4 max-length)) "s https://github.com/hledgerorg/hledger/issues/%s\n")))
          (dolist (num nums)
            (insert
             (format fmt (format "[#%s]:" num) num))))
      )
    )
  ))
