exports.handler = async (event) => {
  console.log('Event:', JSON.stringify(event));
        
  // Exemple de réponse pour un login
  return {
    statusCode: 200,
    headers: {
      'Content-Type': 'application/json',
      'Access-Control-Allow-Origin': '*'  // CORS pour le frontend
    },
    body: JSON.stringify({
      message: 'InfoLine Auth Service - Hello World!',
      timestamp: new Date().toISOString()
    })
  };
};
