

import React, { useEffect, useState, useMemo } from 'react';

const cardStyle = {
	background: '#fff',
	borderRadius: 12,
	boxShadow: '0 2px 8px rgba(0,0,0,0.08)',
	padding: '1.5rem',
	marginBottom: '2rem',
	maxWidth: 1100,
	marginLeft: 'auto',
	marginRight: 'auto',
};

const panelStyle = {
	background: '#f5f7fa',
	borderRadius: 8,
	padding: '1rem',
	marginBottom: '1.5rem',
};

const statusColors = {
	available: '#4caf50',
	'in use': '#2196f3',
	'almost done': '#ff9800',
	'end of cycle': '#9c27b0',
	'out of order': '#f44336',
	'not online': '#bdbdbd',
	default: '#607d8b',
};

function WeeklyHeatmap({ weekStats }) {
	const weekdays = useMemo(() => ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'], []);
	const hours = useMemo(() => Array.from({ length: 24 }, (_, i) => i), []);
	const formatHour = (hour) => {
		const h = hour % 12 === 0 ? 12 : hour % 12;
		const ampm = hour < 12 ? 'AM' : 'PM';
		return `${h} ${ampm}`;
	};

	// Hour filter state
	const [startHour, setStartHour] = useState(0);
	const [endHour, setEndHour] = useState(23);

	const maxAvail = useMemo(() => {
		let max = 1;
		for (const day of weekdays) {
			const stats = weekStats[day];
			if (!stats) continue;
			for (const h of hours) {
				const cell = stats[h];
				if (cell && cell.available > max) max = cell.available;
			}
		}
		return max;
	}, [weekStats, weekdays, hours]);

	const getCellStyle = (percent, isFree, noData) => {
		if (noData) return { background: '#e0e0e0', color: '#757575', fontWeight: 700, fontStyle: 'italic' };
		if (isFree) return { background: '#00e676', color: '#004d40', fontWeight: 700, border: '2px solid #00bfa5' };
		if (percent >= 0.66) return { background: '#a5d6a7', color: '#1b5e20', fontWeight: 700 };
		if (percent >= 0.33) return { background: '#ffe082', color: '#f57c00', fontWeight: 700 }; // orange for medium
		return { background: '#ef9a9a', color: '#b71c1c', fontWeight: 700 };
	};

	// Only show hours in the selected range
	const filteredHours = useMemo(() => {
		if (startHour > endHour) return [];
		return hours.filter(h => h >= startHour && h <= endHour);
	}, [hours, startHour, endHour]);

	const renderTableBody = useMemo(() => (
		filteredHours.map(hour => (
			<tr key={hour}>
				<td style={{ position: 'sticky', left: 0, background: '#fff', fontWeight: 'bold', zIndex: 1, borderRight: '2px solid #e0e0e0', minWidth: 60 }}>{formatHour(hour)}</td>
				{weekdays.map(day => {
					const cell = weekStats[day]?.[hour];
					const noData = !cell || cell.total === 0;
					const avail = cell?.available || 0;
					const total = cell?.total || 0;
					const inUse = cell?.inUse || 0;
					const percent = maxAvail ? avail / maxAvail : 0;
					const isFree = total > 0 && inUse === 0;
					let label = 'Low';
					if (noData) label = 'No Data';
					else if (isFree) label = 'Available';
					else if (inUse === 1) label = 'High';
					else if (percent >= 0.33) label = 'Medium';
					const style = {
						...getCellStyle(percent, isFree, noData),
						textAlign: 'center',
						minWidth: 60,
						padding: 8,
						border: '1px solid #e0e0e0',
						borderLeft: day === 'Sun' ? '2px solid #e0e0e0' : undefined,
						borderRight: day === 'Sat' ? '2px solid #e0e0e0' : undefined,
						cursor: 'pointer',
					};
					let tooltip;
					if (noData) {
						tooltip = 'No data for this slot';
					} else {
						let availStr = Number.isFinite(avail) && !Number.isInteger(avail) ? avail.toFixed(2) : avail;
						let inUseStr = Number.isFinite(inUse) && !Number.isInteger(inUse) ? inUse.toFixed(2) : inUse;
						tooltip = `Available: ${availStr}${cell ? ", In Use: " + inUseStr : ''}`;
					}
					return (
						<td key={day} style={style} title={tooltip}>{label}</td>
					);
				})}
			</tr>
		))
	), [filteredHours, weekdays, weekStats, maxAvail]);

	return (
		<div style={{ overflowX: 'auto', margin: '2rem 0' }}>
			{/* Hour filter controls */}
			<div style={{ marginBottom: 16, display: 'flex', alignItems: 'center', gap: 16 }}>
				<label>Start Hour:
					<select value={startHour} onChange={e => setStartHour(Number(e.target.value))} style={{ marginLeft: 6 }}>
						{hours.map(h => <option key={h} value={h}>{formatHour(h)}</option>)}
					</select>
				</label>
				<label>End Hour:
					<select value={endHour} onChange={e => setEndHour(Number(e.target.value))} style={{ marginLeft: 6 }}>
						{hours.map(h => <option key={h} value={h}>{formatHour(h)}</option>)}
					</select>
				</label>
				{startHour > endHour && <span style={{ color: 'red', marginLeft: 12 }}>Start hour must be before end hour</span>}
			</div>
			<table style={{ borderCollapse: 'separate', borderSpacing: 0, minWidth: 950, fontSize: 16, background: '#fafbfc', borderRadius: 10, overflow: 'hidden' }}>
				<thead>
					<tr>
						<th style={{ position: 'sticky', left: 0, background: '#fff', zIndex: 2, minWidth: 60, fontSize: 15, fontWeight: 700, borderBottom: '2px solid #e0e0e0' }}>Hour</th>
						{weekdays.map(day => <th key={day} style={{ background: '#e3f2fd', fontWeight: 700, fontSize: 15, borderBottom: '2px solid #e0e0e0' }}>{day}</th>)}
					</tr>
				</thead>
				<tbody>
					{renderTableBody}
				</tbody>
			</table>
			<div style={{ fontSize: 15, marginTop: 12, display: 'flex', gap: 18, alignItems: 'center' }}>
				<span style={{ background: '#ef9a9a', color: '#b71c1c', padding: '2px 14px', borderRadius: 6, fontWeight: 700, fontSize: 15 }}>Low</span>
				<span style={{ background: '#ffe082', color: '#f57c00', padding: '2px 14px', borderRadius: 6, fontWeight: 700, fontSize: 15 }}>Medium</span>
				<span style={{ background: '#a5d6a7', color: '#1b5e20', padding: '2px 14px', borderRadius: 6, fontWeight: 700, fontSize: 15 }}>High</span>
				<span style={{ background: '#00e676', color: '#004d40', padding: '2px 14px', borderRadius: 6, fontWeight: 700, border: '2px solid #00bfa5', fontSize: 15 }}>Available</span>
				<span style={{ background: '#e0e0e0', color: '#757575', padding: '2px 14px', borderRadius: 6, fontWeight: 700, fontStyle: 'italic', fontSize: 15 }}>No Data</span>
				<span style={{ marginLeft: 18, color: '#607d8b', fontSize: 13 }}><b>Tip:</b> Hover a cell for details</span>
			</div>
		</div>
	);
}

function App() {
	const [bestTimes, setBestTimes] = useState([]);
	const [machines, setMachines] = useState([]);
	const [loading, setLoading] = useState(true);
	const [error, setError] = useState(null);
	const [machineAnalytics, setMachineAnalytics] = useState([]);
	const [weekStats, setWeekStats] = useState({});
	const [lastUpdated, setLastUpdated] = useState(null);
	const [isRefreshing, setIsRefreshing] = useState(false);

	const [dormFilter, setDormFilter] = useState(() => localStorage.getItem('favoriteDorm') || 'All dorms');
	const [typeFilter, setTypeFilter] = useState('All');
	const [statusFilter, setStatusFilter] = useState('All');

	useEffect(() => {
		function fetchAll() {
			setIsRefreshing(true);
			setError(null);
			
			// Fetch best times
			fetch('/api/laundry/best-times')
				.then((res) => {
					if (!res.ok) throw new Error('Failed to fetch best times');
					return res.json();
				})
				.then((data) => {
					setBestTimes(data.bestTimes || []);
				})
				.catch((err) => {
					console.error('Best times error:', err);
				});
			
			// Fetch current machines
			fetch('/api/laundry')
				.then((res) => {
					if (!res.ok) throw new Error('Failed to fetch machine data');
					return res.json();
				})
				.then((data) => {
					setMachines(data.machines || []);
					setLoading(false);
					setIsRefreshing(false);
					setLastUpdated(new Date());
				})
				.catch((err) => {
					setError('Unable to connect to server. Please check your connection.');
					setLoading(false);
					setIsRefreshing(false);
					console.error('Machine data error:', err);
				});
			
			// Fetch weekly machine analytics by default
			fetch('/api/laundry/machine-analytics?period=week')
				.then((res) => {
					if (!res.ok) throw new Error('Failed to fetch analytics');
					return res.json();
				})
				.then((data) => {
					setMachineAnalytics(data.machineAnalytics || []);
				})
				.catch((err) => {
					console.error('Analytics error:', err);
				});
			
			// Fetch weekly time-slot stats for heatmap (per dorm)
			// Build query params for dorm, type, and status
			const params = [];
			if (dormFilter !== 'All dorms') {
				const normalizedDorm = dormFilter.trim().toLowerCase();
				params.push(`dorm=${encodeURIComponent(normalizedDorm)}`);
			}
			if (typeFilter !== 'All') {
				params.push(`type=${encodeURIComponent(typeFilter.trim().toLowerCase())}`);
			}
			if (statusFilter !== 'All') {
				params.push(`status=${encodeURIComponent(statusFilter.trim().toLowerCase())}`);
			}
			const query = params.length ? `?${params.join('&')}` : '';
			fetch(`/api/laundry/weekly-times${query}`)
				.then((res) => {
					if (!res.ok) throw new Error('Failed to fetch weekly stats');
					return res.json();
				})
				.then((data) => {
					setWeekStats(data.weekStats || {});
				})
				.catch((err) => {
					console.error('Weekly stats error:', err);
				});
		}
		fetchAll();
		const interval = setInterval(fetchAll, 5 * 60 * 1000); // 5 minutes
		return () => clearInterval(interval);
	}, [dormFilter, typeFilter, statusFilter]);

	// Save favorite dorm
	const saveFavoriteDorm = () => {
		if (dormFilter !== 'All dorms') {
			localStorage.setItem('favoriteDorm', dormFilter);
			alert(`Saved ${dormFilter} as your favorite dorm!`);
		}
	};

	// Go to favorite dorm
	const goToFavoriteDorm = () => {
		const fav = localStorage.getItem('favoriteDorm');
		if (fav && dorms.includes(fav)) {
			setDormFilter(fav);
		}
	};

	// Get unique dorms, types, and statuses for filter dropdowns (memoized)
	const dorms = useMemo(() => {
		const uniqueDorms = Array.from(new Set(machines.map(m => m.dorm))).sort();
		return ['All dorms', ...uniqueDorms];
	}, [machines]);
	const types = useMemo(() => ['All', ...Array.from(new Set(machines.map(m => m.type)))], [machines]);
	const statuses = useMemo(() => ['All', ...Array.from(new Set(machines.map(m => m.status)))], [machines]);

	// Filter machines based on user selection (memoized)
	const filteredMachines = useMemo(() => machines.filter(m =>
		(dormFilter === 'All dorms' || m.dorm === dormFilter) &&
		(typeFilter === 'All' || m.type === typeFilter) &&
		(statusFilter === 'All' || m.status === statusFilter)
	), [machines, dormFilter, typeFilter, statusFilter]);

	// For analytics, use all machines if 'All dorms' is selected, otherwise filter by dorm
	const analyticsMachines = useMemo(() => {
		if (dormFilter === 'All dorms') {
			return machines.filter(m =>
				(typeFilter === 'All' || m.type === typeFilter) &&
				(statusFilter === 'All' || m.status === statusFilter)
			);
		} else {
			return filteredMachines;
		}
	}, [machines, dormFilter, typeFilter, statusFilter, filteredMachines]);

	const currentAvailableCount = useMemo(() => analyticsMachines.filter(m =>
		/available/i.test(m.status)
	).length, [analyticsMachines]);

	const formatLastUpdated = () => {
		if (!lastUpdated) return 'Never';
		const now = new Date();
		const diff = Math.floor((now - lastUpdated) / 1000);
		if (diff < 60) return 'Just now';
		if (diff < 3600) return `${Math.floor(diff / 60)} min ago`;
		return lastUpdated.toLocaleTimeString();
	};

		return (
			<div style={{ background: '#f0f2f5', minHeight: '100vh', fontFamily: 'Arial', padding: '2rem 0' }}>
				<div style={{ ...cardStyle, marginBottom: 32 }}>
					<h1 style={{ margin: 0, fontSize: 32, color: '#1976d2', letterSpacing: 1 }}>Conn College Laundry Analytics</h1>
					<div style={{ color: '#607d8b', fontSize: 16, marginTop: 8, display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: 8 }}>
						<span>Find the best time to do your laundry in your dorm.</span>
						<span style={{ fontSize: 14, color: isRefreshing ? '#2196f3' : '#9e9e9e' }}>
							{isRefreshing ? '🔄 Refreshing...' : `Last updated: ${formatLastUpdated()}`}
						</span>
					</div>
				</div>

				<div style={cardStyle}>
					{loading && (
						<div style={{ textAlign: 'center', padding: '3rem' }}>
							<div style={{ fontSize: 48, marginBottom: 16 }}>🔄</div>
							<div style={{ color: '#607d8b', fontSize: 18 }}>Loading laundry data...</div>
						</div>
					)}
					{error && (
						<div style={{ background: '#ffebee', border: '1px solid #ef5350', borderRadius: 8, padding: '1rem', marginBottom: '1rem', color: '#c62828' }}>
							<strong>⚠️ Error:</strong> {error}
						</div>
					)}
					{!loading && !error && (
					<>
					<div style={{ ...panelStyle, display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
						<span style={{ fontWeight: 600, fontSize: 18 }}>Current total available machines:</span>
						<span style={{ fontWeight: 700, fontSize: 22, color: '#4caf50' }}>{currentAvailableCount}</span>
					</div>

					<div style={{ ...panelStyle, marginBottom: 24 }}>
						<h2 style={{ margin: 0, fontSize: 22, color: '#1976d2' }}>Filters</h2>
						<div style={{ display: 'flex', flexWrap: 'wrap', gap: 16, alignItems: 'center', marginTop: 12 }}>
											<label>Dorm:
												<select value={dormFilter} onChange={e => setDormFilter(e.target.value)} style={{ marginLeft: 6 }}>
													{dorms.map(dorm => <option key={dorm} value={dorm}>{dorm}</option>)}
												</select>
											</label>
											<button style={{ marginLeft: 8, background: '#1976d2', color: '#fff', border: 'none', borderRadius: 4, padding: '4px 12px', cursor: dormFilter === 'All dorms' ? 'not-allowed' : 'pointer', opacity: dormFilter === 'All dorms' ? 0.5 : 1 }} onClick={saveFavoriteDorm} disabled={dormFilter === 'All dorms'}>
												Set as Favorite
											</button>
											<button style={{ marginLeft: 8, background: '#43a047', color: '#fff', border: 'none', borderRadius: 4, padding: '4px 12px', cursor: 'pointer' }} onClick={goToFavoriteDorm}>
												Go to Favorite
											</button>
							<label>Type:
								<select value={typeFilter} onChange={e => setTypeFilter(e.target.value)} style={{ marginLeft: 6 }}>
									{types.map(type => <option key={type} value={type}>{type}</option>)}
								</select>
							</label>
							<label>Status:
								<select value={statusFilter} onChange={e => setStatusFilter(e.target.value)} style={{ marginLeft: 6 }}>
									{statuses.map(status => <option key={status} value={status}>{status}</option>)}
								</select>
							</label>
						</div>
					</div>

									{/* Only show machine list if a specific dorm is selected */}
									{dormFilter !== 'All dorms' && (
									  <div style={{ ...panelStyle, marginBottom: 0 }}>
									    <h2 style={{ margin: 0, fontSize: 22, color: '#1976d2' }}>Current Machine Status</h2>
									    <div style={{ display: 'flex', flexDirection: 'column', gap: 8, marginTop: 12 }}>
									      {filteredMachines.length === 0 && !loading && <div style={{ color: '#b71c1c', fontWeight: 500 }}>No machines match your criteria.</div>}
									      {filteredMachines.map((m, idx) => {
									        let icon = '🔧';
									        const type = (m.type || '').toLowerCase();
									        const status = (m.status || '').toLowerCase();
											if (type.includes('washer')) icon = '🧺';
									        else if (type.includes('dryer')) icon = '💨';
									        if (status.includes('out of order')) icon = '❌';
									        const color = statusColors[status] || statusColors.default;
									        return (
									          <div key={idx} style={{
									            display: 'flex', alignItems: 'center', background: '#fff', borderRadius: 6, boxShadow: '0 1px 4px rgba(0,0,0,0.04)',
									            padding: '8px 14px', borderLeft: `6px solid ${color}`
									          }}>
									            <span style={{ fontSize: '1.5rem', marginRight: 12 }}>{icon}</span>
									            <span style={{ fontWeight: 600, minWidth: 90 }}>{m.type} {m.machine}</span>
									            <span style={{ marginLeft: 12, color }}>{m.status}</span>
									            <span style={{ marginLeft: 18, color: '#607d8b', fontSize: 13 }}>{m.timeRemaining ? m.timeRemaining : 'N/A or Open'}</span>
									          </div>
									        );
									      })}
									    </div>
									  </div>
									)}
					</>
					)}
				</div>

						{/* Weekly Heatmap: Show for all dorms and specific dorms */}
						{!loading && !error && (
						<div style={cardStyle}>
													<h2 style={{ marginTop: 0, fontSize: 22, color: '#1976d2' }}>Weekly Machine Availability Heatmap</h2>
													<div style={{ fontSize: 17, color: '#607d8b', marginBottom: 8 }}>
														Showing for: <b>{dormFilter}</b>
													</div>
							<WeeklyHeatmap weekStats={weekStats} />
						</div>
						)}
			</div>
		);
}

export default App;
