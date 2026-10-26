# Make Rich's existing broken-pipe check independent of consumer scheduling.
# Runtime sources and the package's enabled test set remain unchanged.
final: prev:
{
  pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
    (pythonFinal: pythonPrev: {
      rich = pythonPrev.rich.overridePythonAttrs (old: {
        patches = (old.patches or [ ]) ++ [ ./rich-broken-pipe-test.patch ];
      });
    })
  ];
}
