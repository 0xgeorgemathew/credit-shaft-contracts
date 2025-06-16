const paymentIntentId = args[0];
const amountToCapture = args[1];

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
      status: "succeeded",
      amountCaptured: amountToCapture || 5000,
      currency: "usd",
      simulation: true,
    })
  );
}

// Build URL with query parameters for POST request
let url = `https://api.stripe.com/v1/payment_intents/${paymentIntentId}/capture`;
if (amountToCapture) {
  url += `?amount_to_capture=${amountToCapture}`;
}

const stripeRequest = Functions.makeHttpRequest({
  url: url,
  method: "POST",
  headers: {
    Authorization: `Bearer ${secrets.STRIPE_SECRET_KEY}`,
  },
});

// Capture the payment
await stripeRequest;

// Check the payment status
const statusResponse = await Functions.makeHttpRequest({
  url: `https://api.stripe.com/v1/payment_intents/${paymentIntentId}`,
  method: "GET",
  headers: {
    Authorization: `Bearer ${secrets.STRIPE_SECRET_KEY}`,
  },
});

const paymentIntent = statusResponse.data;
return Functions.encodeString(
  JSON.stringify({
    success: paymentIntent.status === "succeeded",
    paymentIntentId: paymentIntent.id,
    status: paymentIntent.status,
    amountCaptured: paymentIntent.amount_received,
    currency: paymentIntent.currency,
  })
);
