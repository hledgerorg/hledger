# File layouts

Some example file layouts, helpful for starting a new hledger setup or for extending an existing one.
Pick one that feels good for now, you can always evolve it later.

- simple:
  Just one file. Good if you want simplicity and manual data entry.

- default: 
  Declarations kept separate for easy maintenance; subdirectories and starter scripts for data-fetching.
  A good standard layout to make things run smoothly, with room to grow.

- years:
  Like default, but with a journal file for each year, and all.journal to combine them.
  Good when you have enough data to make a single file slow.

- year-dirs:
  Each year's files kept in their own directory; years can be combined or not.
  Adds more complexity, but good if you want each year to be self-contained.

simple, default and years are built in to hledger, and `hledger init [--layout LAYOUT]` can write them for you.
Their files are kept in [hledger/embeddedfiles/file-layouts](../../hledger/embeddedfiles/file-layouts);
the directories here are symbolic links to those.
(When written by init, years' 2026.journal is named for the current year, and 2026 in its content is replaced also.)
year-dirs is not built in.
