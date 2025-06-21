// src/StripeSources.sol

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract StripeSources {
    /**
     * @notice Returns the JavaScript source code for capturing a Stripe Payment Intent.
     * @dev This is called by the main contract and passed to a Chainlink Functions request.
     */
    function _getStripeChargeSource() internal pure returns (string memory) {
        return
        "const a=args[0],b=args[1],k=secrets.STRIPE_SECRET_KEY;if(!k)throw Error('Key required');if(!a)throw Error('ID required');if(k.includes('mock'))return Functions.encodeString(JSON.stringify({success:true,paymentIntentId:a,status:'succeeded',amountCaptured:b||5000,currency:'usd',simulation:true}));let u=`https://api.stripe.com/v1/payment_intents/${a}/capture`;if(b)u+=`?amount_to_capture=${b}`;const h={Authorization:`Bearer ${k}`};await Functions.makeHttpRequest({url:u,method:'POST',headers:h});const r=await Functions.makeHttpRequest({url:`https://api.stripe.com/v1/payment_intents/${a}`,method:'GET',headers:h});const p=r.data;return Functions.encodeString(JSON.stringify({success:p.status==='succeeded',paymentIntentId:p.id,status:p.status,amountCaptured:p.amount_received,currency:p.currency}));";
    }

    /**
     * @notice Returns the JavaScript source code for canceling (releasing) a Stripe Payment Intent.
     * @dev This is called by the main contract and passed to a Chainlink Functions request.
     */
    function _getStripeReleaseSource() internal pure returns (string memory) {
        return
        "const a=args[0],k=secrets.STRIPE_SECRET_KEY;if(!k)throw Error('Key required');if(!a)throw Error('ID required');if(k.includes('mock'))return Functions.encodeString(JSON.stringify({success:true,paymentIntentId:a,status:'canceled',simulation:true}));const h={Authorization:`Bearer ${k}`};await Functions.makeHttpRequest({url:`https://api.stripe.com/v1/payment_intents/${a}/cancel`,method:'POST',headers:h});const r=await Functions.makeHttpRequest({url:`https://api.stripe.com/v1/payment_intents/${a}`,method:'GET',headers:h});if(r.error)throw new Error('Check failed');const p=r.data;return Functions.encodeString(JSON.stringify({success:p.status==='canceled',paymentIntentId:p.id,status:p.status}));";
    }
}
