# File layouts

Some example file layouts, helpful for starting a new hledger setup or for extending an existing one.
Pick one that feels good for now, you can always evolve it later.

- simple:
  Just one file. Good if you want simplicity and manual data entry.

- default: 
  Declarations kept separate for easy maintenance; subdirectories and starter scripts for data-fetching.
  A good standard layout to make things run smoothly, with room to grow.

- year-dirs:
  Each year's files kept in their own directory; years can be combined or not.
  Adds some complexity, but good when you have enough data to make a single file slow.

simple and default are built in to hledger, and `hledger init` can write them for you.
Their files are kept in [hledger/embeddedfiles/file-layouts](../../hledger/embeddedfiles/file-layouts);
the simple and default directories here are symbolic links to those.
