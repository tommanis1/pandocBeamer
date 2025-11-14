---
bibliography: bib.bib
---

# P4


* Programming Protocol-independent Packet Processors (P4)
  * A domain-specific language for network devices (switches, NICs, routers, filters, etc.) 
<!-- cite p4.org -->

::: {.figure}
```{=tex}
\tikz{\cat{img/fullPath.tikz}, width=50% .centered}
```
<span class="caption">P4 Network Vision</span>
:::

P4 switches provide an guarantee on the per-packet processing time

* The control plane provides orchestration and manages topology changes
* In practice: offload computation to the data plane where feasible to minimize latency


# Basic Forwarding
 -->

:::: {.columns style="align-items: center;"}
::: {.column width="40%"}

```{=tex}
\tikz{\cat{img/basicForwardingMinimalTopology.tikz}, width=100% .centered}
```
:::

::: {.column width="60%"}
<span style="color: #e74c3c;">1.</span> Update the source and destination MAC addresses

<span style="color: #3498db;">2.</span> Decrement the time-to-live (TTL) in the IP header

<span style="color: #2ecc71;">3.</span> Send the packet out the appropriate port

<div class="codebox" style="visibility: hidden;">
  <div class="codebox-header">(Very) Basic Forwarding</div>
  <pre><code class="fit-text">\cat{p4/basic.p4}</code></pre>
</div>
:::
::::

# Basic Forwarding

:::: {.columns style="align-items: center;"}
::: {.column width="40%"}
```{=tex}
\tikz{\cat{img/basicForwardingMinimalTopologyActionTable.tikz}, width=100% .centered}
```
:::

::: {.column width="60%"}
<span style="color: #e74c3c;">1.</span> Update the source and destination MAC addresses

<span style="color: #3498db;">2.</span> Decrement the time-to-live (TTL) in the IP header

<span style="color: #2ecc71;">3.</span> Send the packet out the appropriate port

<div class="codebox" data-scroll-to="action ipv4_forward" data-highlight-lines="79:#e74c3c,80:#e74c3c,81:#3498db,78:#2ecc71">
  <div class="codebox-header">(Very) Basic Forwarding</div>
  <pre><code class="fit-text">\cat{p4/basic.p4}</code></pre>
</div>
:::
::::





# Summary

- When an identifier bound to <code style="background-color: #f4f4f4; padding: 2px 4px; border-radius: 3px; font-family: monospace; font-size: 0.9em;">Undefined</code> is accessed, it gets automatically bound to a randomly generated value

- <code style="background-color: #f4f4f4; padding: 2px 4px; border-radius: 3px; font-family: monospace; font-size: 0.9em;">require(e)</code> to constrain the search space:

  1.
    - Translate expression <code style="background-color: #f4f4f4; padding: 2px 4px; border-radius: 3px; font-family: monospace; font-size: 0.9em;">e</code> to a Z3 model
    - Extract satisfying values from the model

  2.
    - If <code style="background-color: #f4f4f4; padding: 2px 4px; border-radius: 3px; font-family: monospace; font-size: 0.9em;">e</code> contains unsupported operations (e.g., function calls)
    - Evaluate <code style="background-color: #f4f4f4; padding: 2px 4px; border-radius: 3px; font-family: monospace; font-size: 0.9em;">e</code> with random value generation enabled
    - If <code style="background-color: #f4f4f4; padding: 2px 4px; border-radius: 3px; font-family: monospace; font-size: 0.9em;">e</code> evaluates to <code style="background-color: #f4f4f4; padding: 2px 4px; border-radius: 3px; font-family: monospace; font-size: 0.9em;">false</code>: retry up to N times
    - If all retries fail: discard the test case

* Limitation: each <code style="background-color: #f4f4f4; padding: 2px 4px; border-radius: 3px; font-family: monospace; font-size: 0.9em;">require</code> generates values independently without considering earlier or later constraints


# a frame


<div class="codebox" style="width: 80%; min-width: 600px;">
<pre style="font-size: 1.5em;"><code class="fit-text">

property ttl_decrements_when_routed(headers h, standard_metadata_t standard_metadata) {
    // Ensure the IPv4 header is valid
    require(h.ipv4.isValid());
    
    // Store the original TTL value
    bit<8> original_ttl = h.ipv4.ttl;
    
    // Apply the ingress control block
    MyIngress.apply(h, standard_metadata);
    
    // Check: If packet is being forwarded (not dropped), TTL should decrement by 1
    // egress_spec == 511 means the packet is dropped
    return (standard_metadata.egress_spec != 511) 
           ? (h.ipv4.ttl == original_ttl - 1) 
           : true;
}

</code></pre>

</div>

# Table

\table{\cat{img/toolComparisontable.tex}}

# References
