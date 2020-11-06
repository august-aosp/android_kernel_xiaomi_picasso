/* SPDX-License-Identifier: GPL-2.0 */
#ifndef _LINUX_TRACE_RECURSION_H
#define _LINUX_TRACE_RECURSION_H

#include <linux/interrupt.h>
#include <linux/sched.h>

#ifdef CONFIG_TRACING

/* Only current can touch trace_recursion */

/*
 * For function tracing recursion:
 *  The order of these bits are important.
 *
 *  When function tracing occurs, the following steps are made:
 *   If arch does not support a ftrace feature:
 *    call internal function (uses INTERNAL bits) which calls...
 *   The function callback, which can use the FTRACE bits to
 *    check for recursion.
 */
enum {
	TRACE_BUFFER_BIT,
	TRACE_BUFFER_NMI_BIT,
	TRACE_BUFFER_IRQ_BIT,
	TRACE_BUFFER_SIRQ_BIT,

	/* Start of function recursion bits */
	TRACE_FTRACE_BIT,
	TRACE_FTRACE_NMI_BIT,
	TRACE_FTRACE_IRQ_BIT,
	TRACE_FTRACE_SIRQ_BIT,
	TRACE_FTRACE_TRANSITION_BIT,

	/* Internal use recursion bits */
	TRACE_INTERNAL_BIT,
	TRACE_INTERNAL_NMI_BIT,
	TRACE_INTERNAL_IRQ_BIT,
	TRACE_INTERNAL_SIRQ_BIT,
	TRACE_INTERNAL_TRANSITION_BIT,

	TRACE_BRANCH_BIT,
/*
 * Abuse of the trace_recursion.
 * As we need a way to maintain state if we are tracing the function
 * graph in irq because we want to trace a particular function that
 * was called in irq context but we have irq tracing off. Since this
 * can only be modified by current, we can reuse trace_recursion.
 */
	TRACE_IRQ_BIT,

	/* Set if the function is in the set_graph_function file */
	TRACE_GRAPH_BIT,

	/*
	 * In the very unlikely case that an interrupt came in
	 * at a start of graph tracing, and we want to trace
	 * the function in that interrupt, the depth can be greater
	 * than zero, because of the preempted start of a previous
	 * trace. In an even more unlikely case, depth could be 2
	 * if a softirq interrupted the start of graph tracing,
	 * followed by an interrupt preempting a start of graph
	 * tracing in the softirq, and depth can even be 3
	 * if an NMI came in at the start of an interrupt function
	 * that preempted a softirq start of a function that
	 * preempted normal context!!!! Luckily, it can't be
	 * greater than 3, so the next two bits are a mask
	 * of what the depth is when we set TRACE_GRAPH_BIT
	 */

	TRACE_GRAPH_DEPTH_START_BIT,
	TRACE_GRAPH_DEPTH_END_BIT,
};

#define trace_recursion_set(bit)	do { (current)->trace_recursion |= (1<<(bit)); } while (0)
#define trace_recursion_clear(bit)	do { (current)->trace_recursion &= ~(1<<(bit)); } while (0)
#define trace_recursion_test(bit)	((current)->trace_recursion & (1<<(bit)))

#define trace_recursion_depth() \
	(((current)->trace_recursion >> TRACE_GRAPH_DEPTH_START_BIT) & 3)
#define trace_recursion_set_depth(depth) \
	do {								\
		current->trace_recursion &=				\
			~(3 << TRACE_GRAPH_DEPTH_START_BIT);		\
		current->trace_recursion |=				\
			((depth) & 3) << TRACE_GRAPH_DEPTH_START_BIT;	\
	} while (0)

#define TRACE_CONTEXT_BITS	4

#define TRACE_FTRACE_START	TRACE_FTRACE_BIT

#define TRACE_LIST_START	TRACE_INTERNAL_BIT

#define TRACE_CONTEXT_MASK	((1 << (TRACE_LIST_START + TRACE_CONTEXT_BITS)) - 1)

enum {
	TRACE_CTX_NMI,
	TRACE_CTX_IRQ,
	TRACE_CTX_SOFTIRQ,
	TRACE_CTX_NORMAL,
	TRACE_CTX_TRANSITION,
};

static __always_inline int trace_get_context_bit(void)
{
	int bit;

	if (in_interrupt()) {
		if (in_nmi())
			bit = TRACE_CTX_NMI;

		else if (in_irq())
			bit = TRACE_CTX_IRQ;
		else
			bit = TRACE_CTX_SOFTIRQ;
	} else
		bit = TRACE_CTX_NORMAL;

	return bit;
}

static __always_inline int trace_test_and_set_recursion(int start)
{
	unsigned int val = current->trace_recursion;
	int bit;

	bit = trace_get_context_bit() + start;
	if (unlikely(val & (1 << bit))) {
		/*
		 * It could be that preempt_count has not been updated during
		 * a switch between contexts. Allow for a single recursion.
		 */
		bit = start + TRACE_CTX_TRANSITION;
		if (trace_recursion_test(bit))
			return -1;
		trace_recursion_set(bit);
		barrier();
		return bit;
	}

	val |= 1 << bit;
	current->trace_recursion = val;
	barrier();

	return bit;
}

static __always_inline void trace_clear_recursion(int bit)
{
	unsigned int val = current->trace_recursion;

	bit = 1 << bit;
	val &= ~bit;

	barrier();
	current->trace_recursion = val;
}

#endif /* CONFIG_TRACING */
#endif /* _LINUX_TRACE_RECURSION_H */
