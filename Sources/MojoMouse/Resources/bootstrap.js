if (window.mojoApp?.name === 'Pointer Profiles') {
  $('#appBrand').textContent = 'pointer';
  document.title = 'Pointer Profiles settings';
}
const previousPage = prefs.getItem('lastPage');
if (
  pages.some(([id]) => id === previousPage) &&
  (!['macros', 'rapid'].includes(previousPage) ||
    (experimentalAvailable && prefs.getItem('experimental') === 'true'))
)
  page = previousPage;
load();
