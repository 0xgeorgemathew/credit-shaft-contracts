const paymentIntentId = args[0];

if (!secrets.STRIPE_SECRET_KEY) {
  throw Error("STRIPE_SECRET_KEY required");
}

if (!paymentIntentId) {
  throw Error("Payment Intent ID required");
}

// Check if this is a simulation (mock key)
const isSimulation = secrets.STRIPE_SECRET_KEY.includes("mock_key_for_simulation");

if (isSimulation) {
  // Return mock response for simulation
  return Functions.encodeString(
    JSON.stringify({
      success: true,
      paymentIntentId: paymentIntentId,
      status: "canceled",
      simulation: true,
    })
  );
}

// 1. First, send the request to cancel the Payment Intent
const cancelUrl = `https://api.stripe.com/v1/payment_intents/${paymentIntentId}/cancel`;
const cancelRequest = Functions.makeHttpRequest({
  url: cancelUrl,
  method: "POST",
  headers: {
    Authorization: `Bearer ${secrets.STRIPE_SECRET_KEY}`,
  },
});

// Wait for the cancellation request to complete
await cancelRequest;

// 2. Second, get the status to confirm it was canceled
const statusUrl = `https://api.stripe.com/v1/payment_intents/${paymentIntentId}`;
const statusResponse = await Functions.makeHttpRequest({
  url: statusUrl,
  method: "GET",
  headers: {
    Authorization: `Bearer ${secrets.STRIPE_SECRET_KEY}`,
  },
});

if (statusResponse.error) {
  throw new Error(
    `Stripe status check failed: ${JSON.stringify(statusResponse)}`
  );
}

const paymentIntent = statusResponse.data;

// Return the final status
return Functions.encodeString(
  JSON.stringify({
    success: paymentIntent.status === "canceled",
    paymentIntentId: paymentIntent.id,
    status: paymentIntent.status,
  })
);
