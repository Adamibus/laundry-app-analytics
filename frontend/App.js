import React, { useEffect, useState } from 'react';

function App() {
  const [bestTimes, setBestTimes] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  useEffect(() => {
    fetch('http://localhost:5000/api/laundry/best-times')
      .then((res) => res.json())
      .then((data) => {
        setBestTimes(data.bestTimes || []);
        setLoading(false);
      })
      .catch((err) => {
        setError('Failed to fetch best times data');
        setLoading(false);
      });
  }, []);

  return (
    <div style={{ padding: '2rem', fontFamily: 'Arial' }}>
      <h1>Best Times for Laundry</h1>
      {loading && <p>Loading...</p>}
      {error && <p style={{ color: 'red' }}>{error}</p>}
      <ul>
        {bestTimes.length === 0 && !loading && <li>No data yet. Please let the logger run for a while.</li>}
        {bestTimes.map((slot, idx) => (
          <li key={idx}>
            {slot.time}: {slot.availableCount} machines available
          </li>
        ))}
      </ul>
    </div>
  );
}

export default App;
