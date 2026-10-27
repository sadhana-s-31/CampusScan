/**
 * CampusScan — Dashboard Controller
 * Live table search, status filtering, and quick registration helpers.
 */

document.addEventListener('DOMContentLoaded', () => {
  initSearchAndFilter();
});

let currentFilter = 'all';

function initSearchAndFilter() {
  const searchInput = document.getElementById('dashboard-search');
  const filterBtns = document.querySelectorAll('.filter-btn');

  if (searchInput) {
    searchInput.addEventListener('input', applyTableFilters);
  }

  filterBtns.forEach(btn => {
    btn.addEventListener('click', (e) => {
      filterBtns.forEach(b => b.classList.remove('active'));
      btn.classList.add('active');
      currentFilter = btn.getAttribute('data-filter') || 'all';
      applyTableFilters();
    });
  });
}

function applyTableFilters() {
  const searchInput = document.getElementById('dashboard-search');
  const query = searchInput ? searchInput.value.trim().toLowerCase() : '';
  const rows = document.querySelectorAll('#students-table tbody tr.student-row');
  const noResults = document.getElementById('no-matching-results');

  let visibleCount = 0;

  rows.forEach(row => {
    const rowStatus = row.getAttribute('data-status');
    const searchData = row.getAttribute('data-search') || '';

    const matchesFilter = (currentFilter === 'all') || (rowStatus === currentFilter);
    const matchesSearch = query === '' || searchData.includes(query);

    if (matchesFilter && matchesSearch) {
      row.style.display = '';
      visibleCount++;
    } else {
      row.style.display = 'none';
    }
  });

  if (noResults) {
    noResults.style.display = (visibleCount === 0 && rows.length > 0) ? 'block' : 'none';
  }
}

/**
 * Admin quick register from table
 */
async function quickRegister(studentId) {
  if (!confirm(`Confirm registration for student ID: ${studentId}?`)) return;

  try {
    const response = await fetch('/api/register', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        student_id: studentId,
        registered_by: 'dashboard_admin'
      })
    });

    const data = await response.json();

    if (response.status === 201) {
      alert(`Student ${studentId} successfully registered!`);
      window.location.reload();
    } else {
      alert(data.message || 'Registration failed.');
      window.location.reload();
    }
  } catch (err) {
    console.error(err);
    alert('Failed to connect to registration service.');
  }
}
