import React, { useEffect, useState } from 'react';

function App() {
  const [bestTimes, setBestTimes] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  useEffect(() => {
    fetch('http://localhost:5000/api/laundry')
      .then((res) => res.json())
      .then((data) => {
        setBestTimes(data.bestTimes);
        setLoading(false);
      })
      .catch((err) => {
        setError('Failed to fetch laundry data');
        setLoading(false);
      });
  }, []);

  return (
    <div style={{ padding: '2rem', fontFamily: 'Arial' }}>
      <h1>Laundry Availability</h1>
      {loading && <p>Loading...</p>}
      {error && <p style={{ color: 'red' }}>{error}</p>}
      <ul>
        {bestTimes.map((slot, idx) => (
          <li key={idx}>
            {slot.day} at {slot.hour}: {slot.available ? 'Available' : 'Busy'}
          </li>
        ))}
      </ul>
    </div>
  );
}

export default App;
