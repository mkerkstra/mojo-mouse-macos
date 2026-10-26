const previousPage = prefs.getItem('lastPage');
if (
  pages.some(([id]) => id === previousPage) &&
  (!['macros', 'rapid'].includes(previousPage) || prefs.getItem('experimental') === 'true')
)
  page = previousPage;
load();
